#!/usr/bin/env python3
"""Store KakaoTalk image attachments from Agent Messenger JSON."""

from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import os
import socket
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

MAX_IMAGE_BYTES = 25 * 1024 * 1024
PHOTO_TYPE = 2
MULTIPHOTO_TYPE = 27
LOG_LEVELS = {"debug": 10, "info": 20, "warn": 30, "error": 40}


def log(level: str, action: str, **context: object) -> None:
    configured = os.environ.get("LOG_LEVEL", "warn").lower()
    if LOG_LEVELS[level] < LOG_LEVELS.get(configured, LOG_LEVELS["warn"]):
        return
    fields = " ".join(f"{key}={value}" for key, value in sorted(context.items()))
    print(f"{level} [context:kakaotalk-media:{action}] {fields}".rstrip(), file=sys.stderr)


def opaque(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:24]


def image_urls(message: dict[str, Any]) -> list[str]:
    attachment = message.get("attachment")
    if not isinstance(attachment, dict):
        return []
    message_type = message.get("type", message.get("message_type"))
    if message_type == PHOTO_TYPE:
        url = attachment.get("url")
        return [url] if isinstance(url, str) and url else []
    if message_type == MULTIPHOTO_TYPE:
        urls = attachment.get("imageUrls")
        if not isinstance(urls, list):
            return []
        return [url for url in urls if isinstance(url, str) and url]
    return []


def require_public_https(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("image URL must be credential-free HTTPS")
    addresses = socket.getaddrinfo(parsed.hostname, parsed.port or 443, type=socket.SOCK_STREAM)
    if not addresses:
        raise ValueError("image host did not resolve")
    for address in addresses:
        if not ipaddress.ip_address(address[4][0]).is_global:
            raise ValueError("image URL resolved to a non-public address")


class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> Any:
        require_public_https(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def image_extension(data: bytes, content_type: str | None) -> str:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return ".gif"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return ".webp"
    if content_type == "image/heic" and b"ftyp" in data[:32]:
        return ".heic"
    raise ValueError("downloaded content is not a supported image")


def download(url: str) -> tuple[bytes, str | None]:
    require_public_https(url)
    request = urllib.request.Request(url, headers={"User-Agent": "Sherpa/0.6 image-reader"})
    opener = urllib.request.build_opener(SafeRedirectHandler())
    with opener.open(request, timeout=30) as response:
        declared = response.headers.get("Content-Length")
        if declared is not None and int(declared) > MAX_IMAGE_BYTES:
            raise ValueError("image exceeds size limit")
        data = response.read(MAX_IMAGE_BYTES + 1)
        if len(data) > MAX_IMAGE_BYTES:
            raise ValueError("image exceeds size limit")
        content_type = response.headers.get_content_type()
    return data, content_type


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    descriptor, temporary = tempfile.mkstemp(prefix=".incoming-", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def default_root() -> Path:
    return Path.home() / "Library" / "Application Support" / "Sherpa" / "context-media"


def parse_messages(data: Any) -> list[dict[str, Any]]:
    if isinstance(data, list):
        messages = data
    elif isinstance(data, dict) and isinstance(data.get("messages"), list):
        messages = data["messages"]
    else:
        raise ValueError("expected a message array or an object containing messages")
    if not all(isinstance(message, dict) for message in messages):
        raise ValueError("every message must be an object")
    return messages


def store(account_id: str, chat_id: str, messages: list[dict[str, Any]], root: Path) -> dict[str, Any]:
    stored: list[dict[str, Any]] = []
    incomplete: list[dict[str, Any]] = []
    for message in messages:
        log_id = message.get("log_id")
        if not isinstance(log_id, (str, int)):
            continue
        log_id = str(log_id)
        urls = image_urls(message)
        message_type = message.get("type", message.get("message_type"))
        if message_type in (PHOTO_TYPE, MULTIPHOTO_TYPE) and not urls:
            incomplete.append({"message_key": opaque(log_id), "reason": "image_url_missing"})
            continue
        for index, url in enumerate(urls):
            try:
                log("info", "download-start", attachment_index=index)
                data, content_type = download(url)
                digest = hashlib.sha256(data).hexdigest()
                extension = image_extension(data, content_type)
                directory = root / "kakaotalk" / opaque(account_id) / opaque(chat_id) / opaque(log_id)
                image_path = directory / f"{digest}{extension}"
                if not image_path.exists():
                    atomic_write(image_path, data)
                metadata = {
                    "source": "kakaotalk",
                    "account_key": opaque(account_id),
                    "conversation_key": opaque(chat_id),
                    "message_key": opaque(log_id),
                    "index": index,
                    "sha256": digest,
                    "bytes": len(data),
                    "media_type": content_type,
                    "path": str(image_path),
                    "analysis_state": "pending",
                }
                atomic_write(
                    directory / f"{digest}.json",
                    json.dumps(metadata, ensure_ascii=False, sort_keys=True).encode("utf-8") + b"\n",
                )
                stored.append(metadata)
                log("info", "download-success", attachment_index=index, bytes=len(data))
            except (OSError, ValueError, urllib.error.URLError) as error:
                log("error", "download-failure", attachment_index=index, error=type(error).__name__)
                incomplete.append({
                    "message_key": opaque(log_id),
                    "index": index,
                    "reason": type(error).__name__,
                })
    return {"stored": stored, "incomplete": incomplete, "checkpoint_safe": not incomplete}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--chat-id", required=True)
    parser.add_argument("--root", type=Path, default=default_root())
    arguments = parser.parse_args()
    try:
        payload = json.load(sys.stdin)
        result = store(arguments.account_id, arguments.chat_id, parse_messages(payload), arguments.root)
        json.dump(result, sys.stdout, ensure_ascii=False, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0 if result["checkpoint_safe"] else 2
    except (OSError, ValueError, json.JSONDecodeError) as error:
        json.dump({"error": type(error).__name__, "checkpoint_safe": False}, sys.stdout)
        sys.stdout.write("\n")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
