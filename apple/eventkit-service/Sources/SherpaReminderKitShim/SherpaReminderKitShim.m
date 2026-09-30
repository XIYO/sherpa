#import <Foundation/Foundation.h>
#import <EventKit/EventKit.h>
#import <ImageIO/ImageIO.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "SherpaReminderKitShim.h"

static NSString *const ProtocolVersion = @"2.0.0";
static NSString *const ApplicationContract = @"sherpa.reminder-private.v2";
static NSString *CurrentOperationID = @"unknown";
static NSString *CurrentCapability = @"unknown";
static NSString *const ImplementationRevision = @"reminder-private-v8";
static const NSUInteger MaxResponseBytes = 1024 * 1024;

typedef NS_ENUM(NSInteger, PrivateWriteResult) {
    PrivateWriteResultSucceeded,
    PrivateWriteResultFailed,
    PrivateWriteResultVerificationFailed,
    PrivateWriteResultTargetNotFound,
};

static BOOL containsNul(NSString *value) {
    for (NSUInteger index = 0; index < value.length; index += 1) {
        if ([value characterAtIndex:index] == 0) return YES;
    }
    return NO;
}

static BOOL dictionaryHasExactlyKeys(NSDictionary *dictionary, NSArray<NSString *> *keys) {
    return [[NSSet setWithArray:dictionary.allKeys]
        isEqualToSet:[NSSet setWithArray:keys]];
}

static BOOL isBoolean(id value) {
    return value == (__bridge id)kCFBooleanTrue || value == (__bridge id)kCFBooleanFalse;
}

static BOOL logLevelAllows(NSString *level) {
    NSString *configured = NSProcessInfo.processInfo.environment[@"LOG_LEVEL"].lowercaseString;
    NSInteger threshold = 30;
    if ([configured isEqual:@"debug"]) threshold = 10;
    else if ([configured isEqual:@"info"]) threshold = 20;
    else if ([configured isEqual:@"error"]) threshold = 40;
    NSInteger value = [level isEqual:@"info"] ? 20 : 40;
    return value >= threshold;
}

static void workerLog(NSString *level, NSString *phase, NSString *capability,
                      NSString *code) {
    if (!logLevelAllows(level)) return;
    NSMutableString *message = [NSMutableString stringWithFormat:
        @"[worker:reminder_private:request:%@] capability=%@",
        phase, capability ?: @"unknown"];
    if (code) [message appendFormat:@" code=%@", code];
    fprintf(stderr, "%s\n", message.UTF8String);
}

static void workerFlagABIDebug(id object, SEL selector, const char *type) {
    NSString *configured = NSProcessInfo.processInfo.environment[@"LOG_LEVEL"].lowercaseString;
    if (![configured isEqual:@"debug"] || !object) return;
    fprintf(stderr,
        "[worker:reminder_private:flagged_abi:debug] runtime_class=%s selector=%s value_type=%s\n",
        NSStringFromClass(object_getClass(object)).UTF8String,
        NSStringFromSelector(selector).UTF8String,
        type ?: "missing");
}

static void workerPrivateDebug(NSString *action, NSString *state) {
    NSString *configured = NSProcessInfo.processInfo.environment[@"LOG_LEVEL"].lowercaseString;
    if (![configured isEqual:@"debug"]) return;
    fprintf(stderr, "[worker:reminder_private:%s:debug] state=%s\n",
        action.UTF8String, state.UTF8String);
}

static void workerPrivateErrorDebug(NSString *action, NSError *error) {
    NSString *configured = NSProcessInfo.processInfo.environment[@"LOG_LEVEL"].lowercaseString;
    if (![configured isEqual:@"debug"] || !error) return;
    fprintf(stderr,
        "[worker:reminder_private:%s:debug] state=failed error_domain=%s error_code=%ld\n",
        action.UTF8String, error.domain.UTF8String, (long)error.code);
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:[NSError class]]) {
        fprintf(stderr,
            "[worker:reminder_private:%s:debug] state=underlying_failure error_domain=%s error_code=%ld\n",
            action.UTF8String, underlying.domain.UTF8String, (long)underlying.code);
    }
}

static void workerPrivateClassDebug(NSString *action, NSString *field, id value) {
    NSString *configured = NSProcessInfo.processInfo.environment[@"LOG_LEVEL"].lowercaseString;
    if (![configured isEqual:@"debug"]) return;
    fprintf(stderr,
        "[worker:reminder_private:%s:debug] field=%s runtime_class=%s\n",
        action.UTF8String, field.UTF8String,
        value ? NSStringFromClass(object_getClass(value)).UTF8String : "missing");
}

static void workerPrivateCountDebug(NSString *action, NSString *field,
                                    NSUInteger count) {
    NSString *configured = NSProcessInfo.processInfo.environment[@"LOG_LEVEL"].lowercaseString;
    if (![configured isEqual:@"debug"]) return;
    fprintf(stderr, "[worker:reminder_private:%s:debug] field=%s count=%lu\n",
        action.UTF8String, field.UTF8String, (unsigned long)count);
}

static BOOL safeIdentifier(id value) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *string = value;
    if (string.length == 0 || [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 128) {
        return NO;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-"];
    return [string rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static NSData *responseData(NSDictionary *response) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:response
                                                   options:NSJSONWritingSortedKeys
                                                     error:&error];
    if (!data || error) return nil;
    if (data.length > MaxResponseBytes) {
        id requestID = [response[@"request_id"] isKindOfClass:[NSString class]]
            ? response[@"request_id"] : @"unknown";
        NSDictionary *bounded = @{
            @"kind": @"response",
            @"protocol_version": ProtocolVersion,
            @"application_contract": ApplicationContract,
            @"request_id": requestID,
            @"operation_id": CurrentOperationID,
            @"capability": CurrentCapability,
            @"status": @"failed",
            @"result": [NSNull null],
            @"effect": @{ @"kind": @"none", @"state": @"not_started" },
            @"evidence": [NSNull null],
            @"error": @{ @"code": @"protocol.result_too_large", @"retry": @"never" },
            @"warnings": @[],
        };
        data = [NSJSONSerialization dataWithJSONObject:bounded
                                                options:NSJSONWritingSortedKeys
                                                  error:&error];
    }
    if (!data || error || data.length > MaxResponseBytes) return nil;
    return data;
}

static NSDictionary *failureWithRetry(NSString *requestID, NSString *code,
                                      NSString *retryHint) {
    return @{
        @"kind": @"response",
        @"protocol_version": ProtocolVersion,
        @"application_contract": ApplicationContract,
        @"request_id": requestID ?: @"unknown",
        @"operation_id": CurrentOperationID,
        @"capability": CurrentCapability,
        @"status": @"failed",
        @"result": [NSNull null],
        @"effect": @{ @"kind": @"none", @"state": @"not_started" },
        @"evidence": [NSNull null],
        @"error": @{ @"code": code, @"retry": retryHint },
        @"warnings": @[],
    };
}

static NSDictionary *failure(NSString *requestID, NSString *code) {
    return failureWithRetry(requestID, code, @"never");
}

static NSDictionary *partialMutation(NSString *requestID, NSDictionary *snapshot) {
    return @{
        @"kind": @"response", @"protocol_version": ProtocolVersion,
        @"application_contract": ApplicationContract,
        @"request_id": requestID, @"operation_id": CurrentOperationID,
        @"capability": CurrentCapability, @"status": @"partial",
        @"result": @{ @"snapshot": snapshot ?: [NSNull null] },
        @"effect": @{ @"kind": @"native_mutation", @"state": @"applied" },
        @"evidence": @{ @"kind": @"native_readback", @"state": @"mismatched" },
        @"error": @{ @"code": @"private.verification_failed", @"retry": @"never" },
        @"warnings": @[],
    };
}

static NSDictionary *success(NSString *requestID, NSDictionary *result,
                             NSArray<NSDictionary *> *report) {
    (void)report;
    NSMutableDictionary *response = [@{
        @"kind": @"response",
        @"protocol_version": ProtocolVersion,
        @"application_contract": ApplicationContract,
        @"request_id": requestID,
        @"operation_id": CurrentOperationID,
        @"capability": CurrentCapability,
        @"status": @"succeeded",
        @"result": result,
        @"effect": @{ @"kind": @"none", @"state": @"not_applicable" },
        @"evidence": [NSNull null],
        @"error": [NSNull null],
        @"warnings": @[],
    } mutableCopy];
    if ([CurrentCapability isEqual:@"reminder.private.authorization.request"]) {
        response[@"effect"] = @{ @"kind": @"authorization_prompt", @"state": @"applied" };
        response[@"evidence"] = @{ @"kind": @"authorization_readback", @"state": @"matched" };
    } else if ([CurrentCapability hasSuffix:@".replace"] || [CurrentCapability hasSuffix:@".set"] || [CurrentCapability hasSuffix:@".assign"] || [CurrentCapability hasSuffix:@".ensure"] || [CurrentCapability hasSuffix:@".add"]) {
        response[@"effect"] = @{ @"kind": @"native_mutation", @"state": @"applied" };
        response[@"evidence"] = @{ @"kind": @"native_readback", @"state": @"matched" };
    }
    return response;
}

static NSDictionary *capability(NSString *name, BOOL frameworkLoaded, BOOL surfacePresent) {
    NSString *state;
    NSString *reason;
    if (!frameworkLoaded) {
        state = @"unavailable";
        reason = @"private.framework_unavailable";
    } else if (!surfacePresent) {
        state = @"incompatible";
        reason = @"private.selector_missing";
    } else {
        state = @"disabled";
        reason = @"private.requires_live_verification";
    }
    BOOL mutation = [name hasSuffix:@".replace"] || [name hasSuffix:@".set"] || [name hasSuffix:@".assign"] || [name hasSuffix:@".ensure"] || [name hasSuffix:@".add"];
    return @{
        @"capability": name,
        @"application_contract": ApplicationContract,
        @"request_schema": [NSString stringWithFormat:@"sherpa.%@.request.v2", name],
        @"success_schema": [NSString stringWithFormat:@"sherpa.%@.success.v2", name],
        @"partial_schema": mutation ? [NSString stringWithFormat:@"sherpa.%@.partial.v2", name] : [NSNull null],
        @"uncertain_schema": mutation ? [NSString stringWithFormat:@"sherpa.%@.uncertain.v2", name] : [NSNull null],
        @"effect": mutation ? @"mutation" : @"read",
        @"required_evidence": mutation ? @"native_readback" : @"none",
        @"artifact_policy": [name isEqual:@"reminder.private.image_attachment.add"] ? @"private_reminder_image" : @"none",
        @"destination": @"none",
        @"state": state,
        @"stable_reason_code": reason,
    };
}

static BOOL instanceSelector(NSString *className, NSString *selectorName) {
    Class type = NSClassFromString(className);
    return type && class_getInstanceMethod(type, NSSelectorFromString(selectorName)) != NULL;
}

static BOOL classSelector(NSString *className, NSString *selectorName) {
    Class type = NSClassFromString(className);
    return type && class_getClassMethod(type, NSSelectorFromString(selectorName)) != NULL;
}

static BOOL allSelectors(NSArray<NSArray<NSString *> *> *requirements) {
    for (NSArray<NSString *> *requirement in requirements) {
        if (requirement.count != 3) return NO;
        BOOL isClassMethod = [requirement[2] isEqualToString:@"class"];
        BOOL present = isClassMethod
            ? classSelector(requirement[0], requirement[1])
            : instanceSelector(requirement[0], requirement[1]);
        if (!present) return NO;
    }
    return YES;
}

typedef NS_ENUM(NSUInteger, PrivateFlagScalarABI) {
    PrivateFlagScalarABIUnsupported,
    PrivateFlagScalarABIBool,
    PrivateFlagScalarABIInteger,
};

static PrivateFlagScalarABI flagScalarABI(const char *type) {
    if (!type) return PrivateFlagScalarABIUnsupported;
    while (*type && strchr("rnNoORV", *type)) type += 1;
    if (strcmp(type, @encode(BOOL)) == 0) return PrivateFlagScalarABIBool;
    if (strcmp(type, @encode(NSInteger)) == 0) return PrivateFlagScalarABIInteger;
    return PrivateFlagScalarABIUnsupported;
}

static PrivateFlagScalarABI methodReturnFlagScalarABI(Method method) {
    if (!method) return PrivateFlagScalarABIUnsupported;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    return flagScalarABI(type);
}

static PrivateFlagScalarABI methodArgumentFlagScalarABI(Method method, unsigned index) {
    if (!method || method_getNumberOfArguments(method) <= index) {
        return PrivateFlagScalarABIUnsupported;
    }
    char type[32] = {0};
    method_getArgumentType(method, index, type, sizeof(type));
    return flagScalarABI(type);
}

static BOOL instanceSelectorReturnsFlagScalar(NSString *className,
                                              NSString *selectorName) {
    Class type = NSClassFromString(className);
    Method method = type
        ? class_getInstanceMethod(type, NSSelectorFromString(selectorName))
        : NULL;
    return methodReturnFlagScalarABI(method) != PrivateFlagScalarABIUnsupported;
}

static BOOL instanceSelectorAcceptsFlagScalar(NSString *className,
                                              NSString *selectorName) {
    Class type = NSClassFromString(className);
    Method method = type
        ? class_getInstanceMethod(type, NSSelectorFromString(selectorName))
        : NULL;
    return methodArgumentFlagScalarABI(method, 2) != PrivateFlagScalarABIUnsupported;
}

static BOOL unsignedIntegerType(const char *type) {
    if (!type) return NO;
    while (*type && strchr("rnNoORV", *type)) type += 1;
    return strcmp(type, @encode(NSUInteger)) == 0;
}

static BOOL instanceSelectorReturnsUnsignedInteger(NSString *className,
                                                   NSString *selectorName) {
    Class type = NSClassFromString(className);
    Method method = type
        ? class_getInstanceMethod(type, NSSelectorFromString(selectorName))
        : NULL;
    if (!method) return NO;
    char encoding[32] = {0};
    method_getReturnType(method, encoding, sizeof(encoding));
    return unsignedIntegerType(encoding);
}

static NSNumber *readUnsignedIntegerScalar(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    const char *returnType = signature.methodReturnType;
    char fallbackType[32] = {0};
    if (!returnType) {
        Method method = class_getInstanceMethod(object_getClass(object), selector);
        if (method) {
            method_getReturnType(method, fallbackType, sizeof(fallbackType));
            returnType = fallbackType;
        }
    }
    if (!unsignedIntegerType(returnType)) return nil;
    return @(((NSUInteger (*)(id, SEL))objc_msgSend)(object, selector));
}

static BOOL readFlagScalar(id object, SEL selector, BOOL *valueOut) {
    if (!object || ![object respondsToSelector:selector] || !valueOut) return NO;
    // REMReminder forwards this selector to REMReminderStorage. Its runtime class
    // therefore has no Method even though the invocation is valid; the forwarded
    // storage method is the ABI contract we must honor.
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    const char *returnType = signature.methodReturnType;
    char fallbackType[32] = {0};
    if (!returnType) {
        Class storage = NSClassFromString(@"REMReminderStorage");
        Method method = storage ? class_getInstanceMethod(storage, selector) : NULL;
        if (method) {
            method_getReturnType(method, fallbackType, sizeof(fallbackType));
            returnType = fallbackType;
        }
    }
    workerFlagABIDebug(object, selector, returnType);
    switch (flagScalarABI(returnType)) {
        case PrivateFlagScalarABIBool:
            *valueOut = ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
            return YES;
        case PrivateFlagScalarABIInteger: {
            NSInteger value = ((NSInteger (*)(id, SEL))objc_msgSend)(object, selector);
            if (value != 0 && value != 1) return NO;
            *valueOut = value == 1;
            return YES;
        }
        case PrivateFlagScalarABIUnsupported:
            return NO;
    }
}

static BOOL writeFlagScalar(id object, SEL selector, BOOL value) {
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    const char *argumentType = signature.numberOfArguments > 2
        ? [signature getArgumentTypeAtIndex:2]
        : NULL;
    char fallbackType[32] = {0};
    if (!argumentType) {
        Class change = NSClassFromString(@"REMReminderFlaggedContextChangeItem");
        Method method = change ? class_getInstanceMethod(change, selector) : NULL;
        if (method && method_getNumberOfArguments(method) > 2) {
            method_getArgumentType(method, 2, fallbackType, sizeof(fallbackType));
            argumentType = fallbackType;
        }
    }
    workerFlagABIDebug(object, selector, argumentType);
    switch (flagScalarABI(argumentType)) {
        case PrivateFlagScalarABIBool:
            ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, value);
            return YES;
        case PrivateFlagScalarABIInteger:
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(
                object, selector, value ? 1 : 0);
            return YES;
        case PrivateFlagScalarABIUnsupported:
            return NO;
    }
}

static NSArray<NSDictionary *> *probeCapabilities(BOOL frameworkLoaded) {
    NSArray *base = @[
        @[@"REMObjectID", @"objectIDWithURL:", @"class"],
        @[@"REMStore", @"fetchReminderWithObjectID:error:", @"instance"],
        @[@"REMSaveRequest", @"initWithStore:", @"instance"],
        @[@"REMSaveRequest", @"updateReminder:", @"instance"],
        @[@"REMSaveRequest", @"saveSynchronouslyWithError:", @"instance"],
    ];
    BOOL basePresent = frameworkLoaded && allSelectors(base);

    BOOL tags = basePresent && allSelectors(@[
        @[@"REMReminderChangeItem", @"hashtagContext", @"instance"],
        @[@"REMReminderHashtagContextChangeItem", @"addHashtagWithType:name:", @"instance"],
        @[@"REMReminderHashtagContextChangeItem", @"removeAllHashtags", @"instance"],
    ]);
    BOOL sections = basePresent && allSelectors(@[
        @[@"REMListSectionsDataView", @"initWithStore:", @"instance"],
        @[@"REMListSectionsDataView", @"fetchListSectionWithReminderID:error:", @"instance"],
        @[@"REMListSectionsDataView", @"fetchListSectionsWithListObjectID:error:", @"instance"],
        @[@"REMSaveRequest", @"updateList:", @"instance"],
        @[@"REMListChangeItem", @"sectionsContextChangeItem", @"instance"],
        @[@"REMListSectionContextChangeItem", @"setUnsavedMembershipsOfRemindersInSections:", @"instance"],
        @[@"REMMembership", @"initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn:", @"instance"],
        @[@"REMMemberships", @"initWithMemberships:", @"instance"],
    ]);
    BOOL hierarchy = basePresent && allSelectors(@[
        @[@"REMReminder", @"subtaskContext", @"instance"],
        @[@"REMReminderSubtaskContext", @"fetchRemindersWithError:", @"instance"],
        @[@"REMReminderChangeItem", @"subtaskContext", @"instance"],
        @[@"REMSaveRequest", @"addReminderWithTitle:toReminderSubtaskContextChangeItem:", @"instance"],
    ]);
    BOOL urlAttachment = basePresent && allSelectors(@[
        @[@"REMReminderChangeItem", @"attachmentContext", @"instance"],
        @[@"REMReminderAttachmentContextChangeItem", @"addURLAttachmentWithURL:", @"instance"],
        @[@"REMReminderAttachmentContextChangeItem", @"removeURLAttachments", @"instance"],
    ]);
    BOOL imageAttachment = basePresent && allSelectors(@[
        @[@"REMReminderChangeItem", @"attachmentContext", @"instance"],
        @[@"REMReminderAttachmentContextChangeItem", @"addImageAttachmentWithURL:width:height:error:", @"instance"],
        @[@"REMFileAttachment", @"fileURL", @"instance"],
    ]) && instanceSelectorReturnsUnsignedInteger(@"REMImageAttachment", @"fileSize")
        && instanceSelectorReturnsUnsignedInteger(@"REMImageAttachment", @"width")
        && instanceSelectorReturnsUnsignedInteger(@"REMImageAttachment", @"height");
    BOOL flagged = basePresent && allSelectors(@[
        @[@"REMReminderChangeItem", @"flaggedContext", @"instance"],
        @[@"REMReminderFlaggedContextChangeItem", @"setFlagged:", @"instance"],
    ]) && instanceSelectorReturnsFlagScalar(@"REMReminderStorage", @"flagged")
        && instanceSelectorAcceptsFlagScalar(
            @"REMReminderFlaggedContextChangeItem", @"setFlagged:");

    return @[
        capability(@"reminder.tags", frameworkLoaded, tags),
        capability(@"reminder.sections", frameworkLoaded, sections),
        capability(@"reminder.hierarchy", frameworkLoaded, hierarchy),
        capability(@"reminder.attachments.url", frameworkLoaded, urlAttachment),
        capability(@"reminder.attachments.image", frameworkLoaded, imageAttachment),
        capability(@"reminder.flagged", frameworkLoaded, flagged),
    ];
}

static NSString *authorizationName(EKAuthorizationStatus status) {
    switch (status) {
        case EKAuthorizationStatusFullAccess: return @"full_access";
        case EKAuthorizationStatusWriteOnly: return @"write_only";
        case EKAuthorizationStatusNotDetermined: return @"not_determined";
        case EKAuthorizationStatusDenied: return @"denied";
        case EKAuthorizationStatusRestricted: return @"restricted";
    }
    return @"unknown";
}

static BOOL hasReminderFullAccess(void) {
    return [EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder]
        == EKAuthorizationStatusFullAccess;
}

static Ivar findIvar(Class type, const char *name) {
    while (type) {
        Ivar value = class_getInstanceVariable(type, name);
        if (value) return value;
        type = class_getSuperclass(type);
    }
    return NULL;
}

static id privateReminder(EKReminder *reminder) {
    if (!reminder) return nil;
    SEL backingSelector = NSSelectorFromString(@"backingObject");
    if (![reminder respondsToSelector:backingSelector]) return nil;
    id backing = ((id (*)(id, SEL))objc_msgSend)(reminder, backingSelector);
    if (!backing) return nil;
    Ivar privateIvar = findIvar([backing class], "_remObject");
    if (!privateIvar) return nil;
    id value = object_getIvar(backing, privateIvar);
    Class reminderClass = NSClassFromString(@"REMReminder");
    return reminderClass && [value isKindOfClass:reminderClass] ? value : nil;
}

static id privateStore(id reminder) {
    if (!reminder) return nil;
    Ivar storeIvar = findIvar([reminder class], "_store");
    id store = storeIvar ? object_getIvar(reminder, storeIvar) : nil;
    if (!store) {
        SEL storeSelector = NSSelectorFromString(@"store");
        if ([reminder respondsToSelector:storeSelector]) {
            store = ((id (*)(id, SEL))objc_msgSend)(reminder, storeSelector);
        }
    }
    Class storeClass = NSClassFromString(@"REMStore");
    return storeClass && [store isKindOfClass:storeClass] ? store : nil;
}

static EKReminder *eventKitReminder(NSString *nativeReference, EKEventStore **storeOut) {
    if (![nativeReference isKindOfClass:[NSString class]] || nativeReference.length == 0
        || nativeReference.length > 4096 || containsNul(nativeReference)) {
        return nil;
    }
    EKEventStore *store = [EKEventStore new];
    EKCalendarItem *item = [store calendarItemWithIdentifier:nativeReference];
    if (storeOut) *storeOut = store;
    return [item isKindOfClass:[EKReminder class]] ? (EKReminder *)item : nil;
}

static id selectorValue(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return object && [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector)
        : nil;
}

static NSArray<NSString *> *readTags(id reminder) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    id values = selectorValue(reminder, @"hashtags");
    if ([values conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id value in values) {
            id name = selectorValue(value, @"name");
            if ([name isKindOfClass:[NSString class]] && [name length] > 0) {
                [result addObject:name];
            }
        }
    }
    [result sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return result;
}

static NSNumber *readFlagged(id reminder) {
    BOOL value = NO;
    return readFlagScalar(reminder, NSSelectorFromString(@"flagged"), &value)
        ? @(value)
        : nil;
}

static NSArray<NSString *> *readURLAttachments(id reminder) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    SEL contextSelector = NSSelectorFromString(@"attachmentContext");
    if (![reminder respondsToSelector:contextSelector]) return result;
    id context = ((id (*)(id, SEL))objc_msgSend)(reminder, contextSelector);
    SEL attachmentsSelector = NSSelectorFromString(@"urlAttachments");
    if (![context respondsToSelector:attachmentsSelector]) return result;
    id attachments = ((id (*)(id, SEL))objc_msgSend)(context, attachmentsSelector);
    if (![attachments conformsToProtocol:@protocol(NSFastEnumeration)]) return result;
    for (id attachment in attachments) {
        SEL urlSelector = NSSelectorFromString(@"url");
        if (![attachment respondsToSelector:urlSelector]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(attachment, urlSelector);
        NSString *string = [value isKindOfClass:[NSURL class]]
            ? [(NSURL *)value absoluteString]
            : ([value isKindOfClass:[NSString class]] ? value : nil);
        if (string.length > 0) [result addObject:string];
    }
    [result sortUsingSelector:@selector(compare:)];
    return result;
}

static NSDictionary *attachmentMetadata(id attachment) {
    Class urlClass = NSClassFromString(@"REMURLAttachment");
    Class imageClass = NSClassFromString(@"REMImageAttachment");
    Class fileClass = NSClassFromString(@"REMFileAttachment");
    NSString *kind = urlClass && [attachment isKindOfClass:urlClass] ? @"url"
        : (imageClass && [attachment isKindOfClass:imageClass] ? @"image"
        : (fileClass && [attachment isKindOfClass:fileClass] ? @"file" : @"unknown"));
    id urlValue = selectorValue(attachment, @"url");
    NSString *url = [urlValue isKindOfClass:[NSURL class]]
        ? [(NSURL *)urlValue absoluteString]
        : ([urlValue isKindOfClass:[NSString class]] ? urlValue : nil);
    id fileURLValue = selectorValue(attachment, @"fileURL");
    NSString *filename = [fileURLValue isKindOfClass:[NSURL class]]
        ? [(NSURL *)fileURLValue lastPathComponent] : nil;
    id mediaType = selectorValue(attachment, @"uti");
    id fileSize = readUnsignedIntegerScalar(attachment, @"fileSize");
    id width = readUnsignedIntegerScalar(attachment, @"width");
    id height = readUnsignedIntegerScalar(attachment, @"height");
    return @{
        @"kind": kind,
        @"url": url ?: [NSNull null],
        @"filename": filename ?: [NSNull null],
        @"media_type": [mediaType isKindOfClass:[NSString class]] ? mediaType : [NSNull null],
        @"size_bytes": [fileSize isKindOfClass:[NSNumber class]] ? fileSize : [NSNull null],
        @"width": [width isKindOfClass:[NSNumber class]] ? width : [NSNull null],
        @"height": [height isKindOfClass:[NSNumber class]] ? height : [NSNull null],
    };
}

static NSArray<NSDictionary *> *readAttachments(id reminder) {
    id context = selectorValue(reminder, @"attachmentContext");
    id attachments = selectorValue(context, @"attachments");
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    if ([attachments conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id attachment in attachments) {
            [result addObject:attachmentMetadata(attachment)];
        }
    }
    return result;
}

static EKReminder *eventKitReminderForPrivateReminder(id reminder,
                                                      EKEventStore *eventStore) {
    id value = selectorValue(reminder, @"daCalendarItemUniqueIdentifier");
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return nil;
    EKCalendarItem *item = [eventStore calendarItemWithIdentifier:value];
    return [item isKindOfClass:[EKReminder class]] ? (EKReminder *)item : nil;
}

static NSArray<NSDictionary *> *readSubtasks(id reminder, EKEventStore *eventStore,
                                              BOOL *succeeded) {
    id context = selectorValue(reminder, @"subtaskContext");
    SEL fetchSelector = NSSelectorFromString(@"fetchRemindersWithError:");
    if (!context || ![context respondsToSelector:fetchSelector]) {
        if (succeeded) *succeeded = NO;
        return @[];
    }
    NSError *error = nil;
    id subtasks = ((id (*)(id, SEL, NSError **))objc_msgSend)(
        context, fetchSelector, &error);
    if (error || ![subtasks conformsToProtocol:@protocol(NSFastEnumeration)]) {
        if (succeeded) *succeeded = NO;
        return @[];
    }
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (id subtask in subtasks) {
        EKReminder *publicSubtask = eventKitReminderForPrivateReminder(subtask, eventStore);
        id privateTitle = selectorValue(subtask, @"title");
        NSString *title = publicSubtask.title
            ?: ([privateTitle isKindOfClass:[NSString class]] ? privateTitle : @"");
        NSString *nativeReference = publicSubtask.calendarItemIdentifier;
        [result addObject:@{
            @"native_locator": nativeReference ?: [NSNull null],
            @"title": title,
            @"completed": publicSubtask ? @(publicSubtask.completed) : @NO,
        }];
    }
    if (succeeded) *succeeded = YES;
    return result;
}

static NSString *readSection(id reminder, BOOL *succeeded) {
    id store = privateStore(reminder);
    id reminderID = selectorValue(reminder, @"remObjectID");
    workerPrivateClassDebug(@"section_read", @"store", store);
    workerPrivateClassDebug(@"section_read", @"reminder_id", reminderID);
    Class viewClass = NSClassFromString(@"REMListSectionsDataView");
    SEL initSelector = NSSelectorFromString(@"initWithStore:");
    if (!store || !reminderID || !viewClass
        || ![viewClass instancesRespondToSelector:initSelector]) {
        workerPrivateDebug(@"section_read", !store ? @"store_unavailable"
            : (!reminderID ? @"reminder_id_unavailable"
            : (!viewClass ? @"view_class_unavailable" : @"view_init_unavailable")));
        if (succeeded) *succeeded = NO;
        return nil;
    }
    id view = ((id (*)(id, SEL, id))objc_msgSend)([viewClass alloc], initSelector, store);
    workerPrivateClassDebug(@"section_read", @"view", view);
    SEL fetchSelector = NSSelectorFromString(@"fetchListSectionWithReminderID:error:");
    if (!view || ![view respondsToSelector:fetchSelector]) {
        workerPrivateDebug(@"section_read", !view ? @"view_unavailable"
            : @"fetch_selector_unavailable");
        if (succeeded) *succeeded = NO;
        return nil;
    }
    NSError *error = nil;
    id section = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(
        view, fetchSelector, reminderID, &error);
    if (error) {
        workerPrivateErrorDebug(@"section_read", error);
        id list = selectorValue(reminder, @"list");
        id listID = selectorValue(list, @"remObjectID");
        SEL allSelector = NSSelectorFromString(@"fetchListSectionsWithListObjectID:error:");
        if (listID && [view respondsToSelector:allSelector]) {
            NSError *allError = nil;
            id all = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(
                view, allSelector, listID, &allError);
            if (allError) workerPrivateErrorDebug(@"section_list", allError);
            else if ([all isKindOfClass:[NSArray class]]) {
                workerPrivateCountDebug(@"section_list", @"sections", [all count]);
                if ([all count] == 0) {
                    workerPrivateDebug(@"section_read", @"absent_empty_list");
                    if (succeeded) *succeeded = YES;
                    return nil;
                }
            }
        }
        if (succeeded) *succeeded = NO;
        return nil;
    }
    id displayName = selectorValue(section, @"displayName");
    workerPrivateDebug(@"section_read", section ? @"value" : @"absent");
    if (succeeded) *succeeded = YES;
    return [displayName isKindOfClass:[NSString class]] ? displayName : nil;
}

static NSDictionary *privateSnapshot(NSString *nativeReference) {
    EKEventStore *eventStore = nil;
    EKReminder *reminder = eventKitReminder(nativeReference, &eventStore);
    id privateObject = privateReminder(reminder);
    if (!privateObject) return nil;
    NSNumber *flagged = readFlagged(privateObject);
    BOOL subtasksRead = NO;
    NSArray *subtasks = readSubtasks(privateObject, eventStore, &subtasksRead);
    BOOL sectionRead = NO;
    NSString *section = readSection(privateObject, &sectionRead);
    return @{
        @"tags": readTags(privateObject),
        @"flagged": flagged ?: [NSNull null],
        @"url_attachments": readURLAttachments(privateObject),
        @"attachments": readAttachments(privateObject),
        @"sections": section ? @[section] : @[],
        @"sections_state": sectionRead ? (section ? @"value" : @"absent") : @"unavailable",
        @"subtasks": subtasks,
        @"subtasks_state": subtasksRead ? (subtasks.count ? @"value" : @"absent") : @"unavailable",
        @"os_version": NSProcessInfo.processInfo.operatingSystemVersionString,
    };
}

static NSArray<NSString *> *validatedTags(id value) {
    if (![value isKindOfClass:[NSArray class]] || [value count] > 64) return nil;
    NSMutableArray<NSString *> *tags = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id rawValue in value) {
        if (![rawValue isKindOfClass:[NSString class]]) return nil;
        NSString *tag = [rawValue stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        while ([tag hasPrefix:@"#"]) tag = [tag substringFromIndex:1];
        if (tag.length == 0 || tag.length > 100 || containsNul(tag)) return nil;
        NSString *key = tag.lowercaseString;
        if (![seen containsObject:key]) {
            [seen addObject:key];
            [tags addObject:tag];
        }
    }
    [tags sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return tags;
}

static NSString *validatedText(id value, NSUInteger maximumLength) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0 || text.length > maximumLength || containsNul(text)) return nil;
    return text;
}

static NSArray<NSString *> *validatedTexts(id value, NSUInteger maximumCount,
                                            NSUInteger maximumLength) {
    if (![value isKindOfClass:[NSArray class]] || [value count] > maximumCount) return nil;
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id rawValue in value) {
        NSString *text = validatedText(rawValue, maximumLength);
        if (!text) return nil;
        [result addObject:text];
    }
    return result;
}

static NSArray<NSString *> *validatedWebURLs(id value) {
    NSArray<NSString *> *strings = validatedTexts(value, 64, 4096);
    if (!strings) return nil;
    NSMutableOrderedSet<NSString *> *unique = [NSMutableOrderedSet orderedSet];
    for (NSString *string in strings) {
        if ([string rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                .location != NSNotFound
            || [string rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet]
                .location != NSNotFound) return nil;
        NSURLComponents *components = [NSURLComponents componentsWithString:string];
        NSString *scheme = components.scheme.lowercaseString;
        if (!components.URL || components.host.length == 0
            || components.percentEncodedUser != nil
            || components.percentEncodedPassword != nil
            || (![scheme isEqual:@"http"] && ![scheme isEqual:@"https"])) return nil;
        [unique addObject:components.URL.absoluteString];
    }
    NSArray<NSString *> *result = unique.array;
    return [result sortedArrayUsingSelector:@selector(compare:)];
}

static BOOL preparePrivateMutation(NSString *nativeReference, EKEventStore **eventStoreOut,
                                   id *privateObjectOut, id *saveOut, id *changeOut) {
    EKEventStore *eventStore = nil;
    EKReminder *reminder = eventKitReminder(nativeReference, &eventStore);
    id privateObject = privateReminder(reminder);
    id store = privateStore(privateObject);
    Class saveClass = NSClassFromString(@"REMSaveRequest");
    SEL initSelector = NSSelectorFromString(@"initWithStore:");
    SEL updateSelector = NSSelectorFromString(@"updateReminder:");
    if (!privateObject || !store || !saveClass
        || ![saveClass instancesRespondToSelector:initSelector]) return NO;
    id save = ((id (*)(id, SEL, id))objc_msgSend)([saveClass alloc], initSelector, store);
    if (!save || ![save respondsToSelector:updateSelector]) return NO;
    id change = ((id (*)(id, SEL, id))objc_msgSend)(save, updateSelector, privateObject);
    if (!change) return NO;
    if (eventStoreOut) *eventStoreOut = eventStore;
    if (privateObjectOut) *privateObjectOut = privateObject;
    if (saveOut) *saveOut = save;
    if (changeOut) *changeOut = change;
    return YES;
}

static PrivateWriteResult savePrivateMutation(id save, EKEventStore *eventStore,
                                              NSString *nativeReference,
                                              NSDictionary **snapshotOut) {
    SEL saveSelector = NSSelectorFromString(@"saveSynchronouslyWithError:");
    if (![save respondsToSelector:saveSelector]) return PrivateWriteResultFailed;
    NSError *error = nil;
    BOOL saved = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(save, saveSelector, &error);
    if (!saved || error) return PrivateWriteResultFailed;
    if ([eventStore respondsToSelector:@selector(refreshSourcesIfNecessary)]) {
        [eventStore refreshSourcesIfNecessary];
    }
    NSDictionary *snapshot = privateSnapshot(nativeReference);
    if (!snapshot) return PrivateWriteResultVerificationFailed;
    if (snapshotOut) *snapshotOut = snapshot;
    return PrivateWriteResultSucceeded;
}

static PrivateWriteResult replaceTags(NSString *nativeReference, NSArray<NSString *> *tags,
                                      NSDictionary **snapshotOut) {
    EKEventStore *eventStore = nil;
    EKReminder *reminder = eventKitReminder(nativeReference, &eventStore);
    id privateObject = privateReminder(reminder);
    id store = privateStore(privateObject);
    Class saveClass = NSClassFromString(@"REMSaveRequest");
    if (!privateObject || !store || !saveClass) return PrivateWriteResultFailed;

    SEL initSelector = NSSelectorFromString(@"initWithStore:");
    id save = ((id (*)(id, SEL, id))objc_msgSend)([saveClass alloc], initSelector, store);
    SEL updateSelector = NSSelectorFromString(@"updateReminder:");
    if (!save || ![save respondsToSelector:updateSelector]) return PrivateWriteResultFailed;
    id change = ((id (*)(id, SEL, id))objc_msgSend)(save, updateSelector, privateObject);
    SEL contextSelector = NSSelectorFromString(@"hashtagContext");
    if (![change respondsToSelector:contextSelector]) return PrivateWriteResultFailed;
    id context = ((id (*)(id, SEL))objc_msgSend)(change, contextSelector);
    SEL removeSelector = NSSelectorFromString(@"removeAllHashtags");
    SEL addSelector = NSSelectorFromString(@"addHashtagWithType:name:");
    if (![context respondsToSelector:removeSelector] || ![context respondsToSelector:addSelector]) {
        return PrivateWriteResultFailed;
    }
    ((void (*)(id, SEL))objc_msgSend)(context, removeSelector);
    for (NSString *tag in tags) {
        ((void (*)(id, SEL, NSInteger, id))objc_msgSend)(context, addSelector, 1, tag);
    }
    SEL saveSelector = NSSelectorFromString(@"saveSynchronouslyWithError:");
    if (![save respondsToSelector:saveSelector]) return PrivateWriteResultFailed;
    NSError *error = nil;
    BOOL saved = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(save, saveSelector, &error);
    if (!saved || error) return PrivateWriteResultFailed;

    if ([eventStore respondsToSelector:@selector(refreshSourcesIfNecessary)]) {
        [eventStore refreshSourcesIfNecessary];
    }
    NSDictionary *snapshot = privateSnapshot(nativeReference);
    if (!snapshot || ![snapshot[@"tags"] isEqualToArray:tags]) {
        return PrivateWriteResultVerificationFailed;
    }
    if (snapshotOut) *snapshotOut = snapshot;
    return PrivateWriteResultSucceeded;
}

static PrivateWriteResult setFlagged(NSString *nativeReference, BOOL flagged,
                                     NSDictionary **snapshotOut) {
    EKEventStore *eventStore = nil;
    id save = nil;
    id change = nil;
    if (!preparePrivateMutation(nativeReference, &eventStore, NULL, &save, &change)) {
        return PrivateWriteResultFailed;
    }
    id context = selectorValue(change, @"flaggedContext");
    SEL setSelector = NSSelectorFromString(@"setFlagged:");
    if (!writeFlagScalar(context, setSelector, flagged)) return PrivateWriteResultFailed;
    NSDictionary *snapshot = nil;
    PrivateWriteResult result = savePrivateMutation(
        save, eventStore, nativeReference, &snapshot);
    if (result != PrivateWriteResultSucceeded) return result;
    if (![snapshot[@"flagged"] isKindOfClass:[NSNumber class]]
        || [snapshot[@"flagged"] boolValue] != flagged) {
        return PrivateWriteResultVerificationFailed;
    }
    if (snapshotOut) *snapshotOut = snapshot;
    return PrivateWriteResultSucceeded;
}

static PrivateWriteResult replaceURLAttachments(NSString *nativeReference,
                                                NSArray<NSString *> *urls,
                                                NSDictionary **snapshotOut) {
    EKEventStore *eventStore = nil;
    id save = nil;
    id change = nil;
    if (!preparePrivateMutation(nativeReference, &eventStore, NULL, &save, &change)) {
        return PrivateWriteResultFailed;
    }
    id context = selectorValue(change, @"attachmentContext");
    SEL removeSelector = NSSelectorFromString(@"removeURLAttachments");
    SEL addSelector = NSSelectorFromString(@"addURLAttachmentWithURL:");
    if (!context || ![context respondsToSelector:removeSelector]
        || ![context respondsToSelector:addSelector]) return PrivateWriteResultFailed;
    ((void (*)(id, SEL))objc_msgSend)(context, removeSelector);
    for (NSString *url in urls) {
        id attachment = ((id (*)(id, SEL, id))objc_msgSend)(
            context, addSelector, [NSURL URLWithString:url]);
        if (!attachment) return PrivateWriteResultFailed;
    }
    NSDictionary *snapshot = nil;
    PrivateWriteResult result = savePrivateMutation(
        save, eventStore, nativeReference, &snapshot);
    if (result != PrivateWriteResultSucceeded) return result;
    if (![snapshot[@"url_attachments"] isEqualToArray:urls]) {
        return PrivateWriteResultVerificationFailed;
    }
    if (snapshotOut) *snapshotOut = snapshot;
    return PrivateWriteResultSucceeded;
}

static NSArray *listSections(id privateObject, id store, NSError **error) {
    id list = selectorValue(privateObject, @"list");
    id listID = selectorValue(list, @"remObjectID");
    Class viewClass = NSClassFromString(@"REMListSectionsDataView");
    SEL initSelector = NSSelectorFromString(@"initWithStore:");
    if (!listID || !viewClass || ![viewClass instancesRespondToSelector:initSelector]) return nil;
    id view = ((id (*)(id, SEL, id))objc_msgSend)([viewClass alloc], initSelector, store);
    SEL fetchSelector = NSSelectorFromString(@"fetchListSectionsWithListObjectID:error:");
    if (!view || ![view respondsToSelector:fetchSelector]) return nil;
    id sections = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(
        view, fetchSelector, listID, error);
    return [sections isKindOfClass:[NSArray class]] ? sections : nil;
}

static NSDictionary *sectionsResponse(NSString *requestID, NSDictionary *payload) {
    if (!dictionaryHasExactlyKeys(payload, @[@"collection_native_locator"])) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSString *listReference = payload[@"collection_native_locator"];
    if (![listReference isKindOfClass:[NSString class]] || listReference.length == 0
        || listReference.length > 4096 || containsNul(listReference)) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    if (!hasReminderFullAccess()) {
        return failureWithRetry(
            requestID, @"private.authorization_required", @"after_user_action");
    }

    EKEventStore *eventStore = [EKEventStore new];
    EKCalendar *calendar = nil;
    for (EKCalendar *candidate in [eventStore calendarsForEntityType:EKEntityTypeReminder]) {
        if ([candidate.calendarIdentifier isEqualToString:listReference]) {
            calendar = candidate;
            break;
        }
    }
    if (!calendar) {
        return failure(requestID, @"private.not_found");
    }
    NSPredicate *predicate = [eventStore predicateForRemindersInCalendars:@[calendar]];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSArray<EKReminder *> *reminders = nil;
    [eventStore fetchRemindersMatchingPredicate:predicate completion:^(NSArray<EKReminder *> *values) {
        reminders = values;
        dispatch_semaphore_signal(semaphore);
    }];
    if (dispatch_semaphore_wait(
            semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)) != 0) {
        return success(requestID, @{ @"sections": @[], @"sections_state": @"unavailable" }, @[]);
    }
    EKReminder *reminder = reminders.firstObject;
    id privateObject = privateReminder(reminder);
    id store = privateStore(privateObject);
    if (!privateObject || !store) {
        return success(requestID, @{ @"sections": @[], @"sections_state": @"unavailable" }, @[]);
    }
    NSError *error = nil;
    NSArray *privateSections = listSections(privateObject, store, &error);
    if (!privateSections || error) {
        return success(requestID, @{ @"sections": @[], @"sections_state": @"unavailable" }, @[]);
    }
    NSMutableArray<NSString *> *sections = [NSMutableArray array];
    for (id section in privateSections) {
        id name = selectorValue(section, @"displayName");
        if (![name isKindOfClass:[NSString class]] || [name length] == 0 || [name length] > 500) {
            return success(requestID, @{ @"sections": @[], @"sections_state": @"unavailable" }, @[]);
        }
        [sections addObject:name];
    }
    return success(requestID, @{
        @"sections": sections,
        @"sections_state": sections.count ? @"value" : @"absent",
    }, @[]);
}

static PrivateWriteResult assignSection(NSString *nativeReference, NSString *name,
                                        NSDictionary **snapshotOut) {
    EKEventStore *eventStore = nil;
    id privateObject = nil;
    id save = nil;
    id change = nil;
    if (!preparePrivateMutation(
            nativeReference, &eventStore, &privateObject, &save, &change)) {
        return PrivateWriteResultFailed;
    }
    id store = privateStore(privateObject);
    NSError *fetchError = nil;
    NSArray *sections = listSections(privateObject, store, &fetchError);
    if (!sections || fetchError) return PrivateWriteResultFailed;
    id targetSectionID = nil;
    for (id section in sections) {
        id sectionID = selectorValue(section, @"remObjectID");
        id displayName = selectorValue(section, @"displayName");
        if ([displayName isKindOfClass:[NSString class]] && [displayName isEqual:name]) {
            targetSectionID = sectionID;
        }
    }
    if (!targetSectionID) return PrivateWriteResultTargetNotFound;
    id list = selectorValue(privateObject, @"list");
    SEL updateListSelector = NSSelectorFromString(@"updateList:");
    if (!list || ![save respondsToSelector:updateListSelector]) return PrivateWriteResultFailed;
    id listChange = ((id (*)(id, SEL, id))objc_msgSend)(save, updateListSelector, list);
    id context = selectorValue(listChange, @"sectionsContextChangeItem");
    SEL membershipSelector =
        NSSelectorFromString(@"setUnsavedMembershipsOfRemindersInSections:");
    if (!context || ![context respondsToSelector:membershipSelector]) {
        return PrivateWriteResultFailed;
    }
    id reminderID = selectorValue(privateObject, @"remObjectID");
    id reminderUUID = selectorValue(reminderID, @"uuid");
    id sectionUUID = selectorValue(targetSectionID, @"uuid");
    Class membershipClass = NSClassFromString(@"REMMembership");
    Class membershipsClass = NSClassFromString(@"REMMemberships");
    SEL membershipInit = NSSelectorFromString(
        @"initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn:");
    SEL membershipsInit = NSSelectorFromString(@"initWithMemberships:");
    if (![reminderUUID isKindOfClass:[NSUUID class]]
        || ![sectionUUID isKindOfClass:[NSUUID class]] || !membershipClass
        || !membershipsClass
        || ![membershipClass instancesRespondToSelector:membershipInit]
        || ![membershipsClass instancesRespondToSelector:membershipsInit]) {
        return PrivateWriteResultFailed;
    }
    id membership = ((id (*)(id, SEL, id, id, BOOL, id))objc_msgSend)(
        [membershipClass alloc], membershipInit, reminderUUID, sectionUUID, NO, [NSDate date]);
    id memberships = ((id (*)(id, SEL, id))objc_msgSend)(
        [membershipsClass alloc], membershipsInit, @[membership]);
    if (!membership || !memberships) return PrivateWriteResultFailed;
    ((void (*)(id, SEL, id))objc_msgSend)(context, membershipSelector, memberships);

    NSDictionary *snapshot = nil;
    PrivateWriteResult result = savePrivateMutation(
        save, eventStore, nativeReference, &snapshot);
    if (result != PrivateWriteResultSucceeded) return result;
    if (![snapshot[@"sections_state"] isEqual:@"value"]
        || ![snapshot[@"sections"] isEqualToArray:@[name]]) {
        return PrivateWriteResultVerificationFailed;
    }
    if (snapshotOut) *snapshotOut = snapshot;
    return PrivateWriteResultSucceeded;
}

static NSCountedSet *titleCounts(NSArray *subtasks) {
    NSCountedSet *counts = [NSCountedSet set];
    for (NSDictionary *subtask in subtasks) {
        id title = subtask[@"title"];
        if ([title isKindOfClass:[NSString class]]) [counts addObject:title];
    }
    return counts;
}

static PrivateWriteResult ensureSubtasks(NSString *nativeReference,
                                         NSArray<NSString *> *titles,
                                         NSDictionary **snapshotOut) {
    NSDictionary *before = privateSnapshot(nativeReference);
    if (!before) return PrivateWriteResultFailed;
    NSCountedSet *existing = titleCounts(before[@"subtasks"]);
    NSCountedSet *requested = [NSCountedSet setWithArray:titles];
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *title in requested) {
        NSUInteger shortage = [requested countForObject:title] -
            MIN([requested countForObject:title], [existing countForObject:title]);
        for (NSUInteger index = 0; index < shortage; index += 1) {
            [missing addObject:title];
        }
    }
    if (missing.count == 0) {
        if (snapshotOut) *snapshotOut = before;
        return PrivateWriteResultSucceeded;
    }
    EKEventStore *eventStore = nil;
    id save = nil;
    id change = nil;
    if (!preparePrivateMutation(nativeReference, &eventStore, NULL, &save, &change)) {
        return PrivateWriteResultFailed;
    }
    id context = selectorValue(change, @"subtaskContext");
    SEL addSelector =
        NSSelectorFromString(@"addReminderWithTitle:toReminderSubtaskContextChangeItem:");
    if (!context || ![save respondsToSelector:addSelector]) return PrivateWriteResultFailed;
    for (NSString *title in missing) {
        id subtask = ((id (*)(id, SEL, id, id))objc_msgSend)(
            save, addSelector, title, context);
        if (!subtask) return PrivateWriteResultFailed;
    }
    NSDictionary *snapshot = nil;
    PrivateWriteResult result = savePrivateMutation(
        save, eventStore, nativeReference, &snapshot);
    if (result != PrivateWriteResultSucceeded) return result;
    NSCountedSet *actual = titleCounts(snapshot[@"subtasks"]);
    for (NSString *title in requested) {
        if ([actual countForObject:title] < [requested countForObject:title]) {
            return PrivateWriteResultVerificationFailed;
        }
    }
    if (snapshotOut) *snapshotOut = snapshot;
    return PrivateWriteResultSucceeded;
}

static NSUInteger imageAttachmentCount(NSDictionary *snapshot) {
    NSUInteger count = 0;
    for (NSDictionary *attachment in snapshot[@"attachments"]) {
        if ([attachment[@"kind"] isEqual:@"image"]) count += 1;
    }
    return count;
}

static NSURL *validatedArtifactURL(NSString *directory, NSString *filename) {
    if (![directory isKindOfClass:[NSString class]] || directory.length == 0
        || directory.length > 4096 || containsNul(directory)
        || ![filename isKindOfClass:[NSString class]] || filename.length == 0
        || filename.length > 255 || containsNul(filename)
        || ![filename.lastPathComponent isEqual:filename]
        || [filename isEqual:@"."] || [filename isEqual:@".."]) return nil;
    NSString *root = directory.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    NSString *candidate = [[root stringByAppendingPathComponent:filename]
        stringByStandardizingPath].stringByResolvingSymlinksInPath;
    NSString *prefix = [root stringByAppendingString:@"/"];
    if (![candidate hasPrefix:prefix]) return nil;
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:candidate error:&error];
    NSNumber *size = attributes[NSFileSize];
    if (error || ![attributes[NSFileType] isEqual:NSFileTypeRegular]
        || ![size isKindOfClass:[NSNumber class]] || size.unsignedLongLongValue == 0
        || size.unsignedLongLongValue > 25ULL * 1024ULL * 1024ULL) return nil;
    return [NSURL fileURLWithPath:candidate isDirectory:NO];
}

static BOOL imageDimensions(NSURL *url, NSUInteger *widthOut, NSUInteger *heightOut) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return NO;
    CFDictionaryRef copied = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!copied) return NO;
    NSDictionary *properties = CFBridgingRelease(copied);
    NSNumber *width = properties[(__bridge NSString *)kCGImagePropertyPixelWidth];
    NSNumber *height = properties[(__bridge NSString *)kCGImagePropertyPixelHeight];
    if (![width isKindOfClass:[NSNumber class]] || ![height isKindOfClass:[NSNumber class]]
        || width.unsignedLongLongValue == 0 || height.unsignedLongLongValue == 0
        || width.unsignedLongLongValue > 100000 || height.unsignedLongLongValue > 100000) {
        return NO;
    }
    if (widthOut) *widthOut = width.unsignedIntegerValue;
    if (heightOut) *heightOut = height.unsignedIntegerValue;
    return YES;
}

static PrivateWriteResult addImageAttachment(NSString *nativeReference, NSURL *artifactURL,
                                             NSString *filename,
                                             NSDictionary **snapshotOut) {
    NSDictionary *before = privateSnapshot(nativeReference);
    if (!before) return PrivateWriteResultFailed;
    for (NSDictionary *attachment in before[@"attachments"]) {
        if ([attachment[@"kind"] isEqual:@"image"]
            && [attachment[@"filename"] isEqual:filename]) {
            if (snapshotOut) *snapshotOut = before;
            return PrivateWriteResultSucceeded;
        }
    }
    NSUInteger width = 0;
    NSUInteger height = 0;
    if (!imageDimensions(artifactURL, &width, &height)) return PrivateWriteResultFailed;
    EKEventStore *eventStore = nil;
    id save = nil;
    id change = nil;
    if (!preparePrivateMutation(nativeReference, &eventStore, NULL, &save, &change)) {
        return PrivateWriteResultFailed;
    }
    id context = selectorValue(change, @"attachmentContext");
    SEL addSelector = NSSelectorFromString(@"addImageAttachmentWithURL:width:height:error:");
    if (!context || ![context respondsToSelector:addSelector]) return PrivateWriteResultFailed;
    NSError *error = nil;
    id attachment = ((id (*)(id, SEL, id, NSUInteger, NSUInteger, NSError **))objc_msgSend)(
        context, addSelector, artifactURL, width, height, &error);
    if (!attachment || error) return PrivateWriteResultFailed;
    NSDictionary *snapshot = nil;
    PrivateWriteResult result = savePrivateMutation(
        save, eventStore, nativeReference, &snapshot);
    if (result != PrivateWriteResultSucceeded) return result;
    if (imageAttachmentCount(snapshot) <= imageAttachmentCount(before)) {
        return PrivateWriteResultVerificationFailed;
    }
    if (snapshotOut) *snapshotOut = snapshot;
    return PrivateWriteResultSucceeded;
}

static NSDictionary *requestAuthorization(NSString *requestID) {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL granted = NO;
    __block NSError *authorizationError = nil;
    EKEventStore *store = [EKEventStore new];
    [store requestFullAccessToRemindersWithCompletion:^(BOOL value, NSError *error) {
        granted = value;
        authorizationError = error;
        dispatch_semaphore_signal(semaphore);
    }];
    long wait = dispatch_semaphore_wait(
        semaphore, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
    if (wait != 0) return failureWithRetry(
        requestID, @"private.authorization_timed_out", @"safe");
    if (!granted || authorizationError) {
        return failureWithRetry(
            requestID, @"private.authorization_required", @"after_user_action");
    }
    return success(requestID, @{
        @"authorization": authorizationName(
            [EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder])
    }, @[]);
}

static BOOL validPolicy(NSDictionary *policy, NSString *effect,
                        NSString *requiredEvidence, BOOL allowsArtifact) {
    NSSet *allowedKeys = [NSSet setWithArray:@[
        @"effect", @"required_evidence", @"artifact_directory"
    ]];
    if (![[NSSet setWithArray:policy.allKeys] isEqualToSet:allowedKeys]
        || ![policy[@"effect"] isKindOfClass:[NSString class]]) return NO;
    if (![policy[@"required_evidence"] isKindOfClass:[NSString class]]) return NO;
    id artifactDirectory = policy[@"artifact_directory"];
    if (artifactDirectory && artifactDirectory != [NSNull null]
        && (![artifactDirectory isKindOfClass:[NSString class]]
            || [artifactDirectory length] == 0
            || [artifactDirectory length] > 4096
            || containsNul(artifactDirectory))) return NO;
    if (!allowsArtifact && artifactDirectory && artifactDirectory != [NSNull null]) return NO;
    return [policy[@"effect"] isEqual:effect]
        && [policy[@"required_evidence"] isEqual:requiredEvidence];
}

static BOOL environmentEnabled(NSString *name) {
    return [NSProcessInfo.processInfo.environment[name] isEqual:@"1"];
}

static BOOL loadPrivateFrameworks(void) {
    const char *reminderKitPath =
        "/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit";
    const char *internalPath =
        "/System/Library/PrivateFrameworks/ReminderKitInternal.framework/ReminderKitInternal";
    void *reminderKit = dlopen(reminderKitPath, RTLD_LAZY | RTLD_LOCAL);
    (void)dlopen(internalPath, RTLD_LAZY | RTLD_LOCAL);
    return reminderKit != NULL;
}

static NSDictionary *authorizationStatus(NSString *requestID) {
    return success(requestID, @{
        @"authorization": authorizationName(
            [EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder])
    }, @[]);
}

static NSDictionary *snapshotResponse(NSString *requestID, NSDictionary *payload) {
    if (!dictionaryHasExactlyKeys(payload, @[@"native_locator"])) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSString *nativeReference = payload[@"native_locator"];
    if (![nativeReference isKindOfClass:[NSString class]] || nativeReference.length == 0
        || nativeReference.length > 4096 || containsNul(nativeReference)) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    if (!hasReminderFullAccess()) {
        return failureWithRetry(
            requestID, @"private.authorization_required", @"after_user_action");
    }
    EKReminder *reminder = eventKitReminder(nativeReference, NULL);
    if (!reminder) return failure(requestID, @"private.not_found");
    if (!privateReminder(reminder)) {
        return failure(requestID, @"private.bridge_incompatible");
    }
    NSDictionary *snapshot = privateSnapshot(nativeReference);
    if (!snapshot) return failure(requestID, @"private.operation_failed");
    return success(requestID, @{@"snapshot": snapshot}, @[]);
}

static NSDictionary *snapshotsResponse(NSString *requestID, NSDictionary *payload) {
    if (!dictionaryHasExactlyKeys(payload, @[@"native_locators"])) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    id references = payload[@"native_locators"];
    if (![references isKindOfClass:[NSArray class]] || [references count] > 200) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    for (id reference in references) {
        if (![reference isKindOfClass:[NSString class]] || [reference length] == 0
            || [reference length] > 4096 || containsNul(reference)) {
            return failure(requestID, @"protocol.invalid_payload");
        }
    }
    if (!hasReminderFullAccess()) {
        return failureWithRetry(
            requestID, @"private.authorization_required", @"after_user_action");
    }
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSString *reference in references) {
        NSDictionary *snapshot = privateSnapshot(reference);
        if (snapshot) {
            [items addObject:@{
                @"native_locator": reference,
                @"status": @"succeeded",
                @"snapshot": snapshot,
                @"stable_error_code": [NSNull null],
            }];
        } else {
            [items addObject:@{
                @"native_locator": reference,
                @"status": @"failed",
                @"snapshot": [NSNull null],
                @"stable_error_code": @"private.not_found_or_incompatible",
            }];
        }
    }
    return success(requestID, @{@"items": items}, @[]);
}

static NSDictionary *replaceTagsResponse(NSString *requestID, NSDictionary *payload) {
    if (!dictionaryHasExactlyKeys(payload, @[@"native_locator", @"tags"])) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSString *nativeReference = payload[@"native_locator"];
    NSArray<NSString *> *tags = validatedTags(payload[@"tags"]);
    if (![nativeReference isKindOfClass:[NSString class]] || nativeReference.length == 0
        || nativeReference.length > 4096 || containsNul(nativeReference) || !tags) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    if (!environmentEnabled(@"SHERPA_PRIVATE_WRITES")) {
        return failureWithRetry(
            requestID, @"private.write_disabled", @"after_user_action");
    }
    if (!hasReminderFullAccess()) {
        return failureWithRetry(
            requestID, @"private.authorization_required", @"after_user_action");
    }
    EKReminder *reminder = eventKitReminder(nativeReference, NULL);
    if (!reminder) return failure(requestID, @"private.not_found");
    if (!privateReminder(reminder)) {
        return failure(requestID, @"private.bridge_incompatible");
    }
    NSDictionary *snapshot = nil;
    switch (replaceTags(nativeReference, tags, &snapshot)) {
        case PrivateWriteResultSucceeded:
            return success(requestID, @{
                @"snapshot": snapshot,
                @"verification": @"verified",
            }, @[]);
        case PrivateWriteResultVerificationFailed:
            return partialMutation(requestID, snapshot);
        case PrivateWriteResultFailed:
            return failure(requestID, @"private.operation_failed");
        case PrivateWriteResultTargetNotFound:
            return failure(requestID, @"private.section_not_found");
    }
}

static NSDictionary *mutationResponse(NSString *requestID, PrivateWriteResult result,
                                      NSDictionary *snapshot) {
    switch (result) {
        case PrivateWriteResultSucceeded:
            return success(requestID, @{
                @"snapshot": snapshot,
                @"verification": @"verified",
            }, @[]);
        case PrivateWriteResultVerificationFailed:
            return partialMutation(requestID, snapshot);
        case PrivateWriteResultFailed:
            return failure(requestID, @"private.operation_failed");
        case PrivateWriteResultTargetNotFound:
            return failure(requestID, @"private.section_not_found");
    }
}

static NSDictionary *writePreflightFailure(NSString *requestID,
                                           NSString *nativeReference) {
    if (!environmentEnabled(@"SHERPA_PRIVATE_WRITES")) {
        return failureWithRetry(
            requestID, @"private.write_disabled", @"after_user_action");
    }
    if (!hasReminderFullAccess()) {
        return failureWithRetry(
            requestID, @"private.authorization_required", @"after_user_action");
    }
    EKReminder *reminder = eventKitReminder(nativeReference, NULL);
    if (!reminder) return failure(requestID, @"private.not_found");
    if (!privateReminder(reminder)) {
        return failure(requestID, @"private.bridge_incompatible");
    }
    return nil;
}

static NSDictionary *setFlaggedResponse(NSString *requestID, NSDictionary *payload) {
    if (!dictionaryHasExactlyKeys(payload, @[@"native_locator", @"flagged"])) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSString *nativeReference = payload[@"native_locator"];
    id flagged = payload[@"flagged"];
    if (![nativeReference isKindOfClass:[NSString class]] || nativeReference.length == 0
        || nativeReference.length > 4096 || containsNul(nativeReference)
        || !isBoolean(flagged)) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSDictionary *preflight = writePreflightFailure(requestID, nativeReference);
    if (preflight) return preflight;
    NSDictionary *snapshot = nil;
    return mutationResponse(
        requestID, setFlagged(nativeReference, [flagged boolValue], &snapshot), snapshot);
}

static NSDictionary *replaceURLAttachmentsResponse(NSString *requestID,
                                                    NSDictionary *payload) {
    if (!dictionaryHasExactlyKeys(payload, @[@"native_locator", @"urls"])) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSString *nativeReference = payload[@"native_locator"];
    NSArray<NSString *> *urls = validatedWebURLs(payload[@"urls"]);
    if (![nativeReference isKindOfClass:[NSString class]] || nativeReference.length == 0
        || nativeReference.length > 4096 || containsNul(nativeReference) || !urls) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSDictionary *preflight = writePreflightFailure(requestID, nativeReference);
    if (preflight) return preflight;
    NSDictionary *snapshot = nil;
    return mutationResponse(
        requestID, replaceURLAttachments(nativeReference, urls, &snapshot), snapshot);
}

static NSDictionary *assignSectionResponse(NSString *requestID, NSDictionary *payload) {
    if (!dictionaryHasExactlyKeys(payload, @[@"native_locator", @"section"])) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSString *nativeReference = payload[@"native_locator"];
    NSString *section = validatedText(payload[@"section"], 500);
    if (![nativeReference isKindOfClass:[NSString class]] || nativeReference.length == 0
        || nativeReference.length > 4096 || containsNul(nativeReference) || !section) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSDictionary *preflight = writePreflightFailure(requestID, nativeReference);
    if (preflight) return preflight;
    NSDictionary *snapshot = nil;
    return mutationResponse(
        requestID, assignSection(nativeReference, section, &snapshot), snapshot);
}

static NSDictionary *ensureSubtasksResponse(NSString *requestID, NSDictionary *payload) {
    if (!dictionaryHasExactlyKeys(payload, @[@"native_locator", @"titles"])) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSString *nativeReference = payload[@"native_locator"];
    NSArray<NSString *> *titles = validatedTexts(payload[@"titles"], 32, 1000);
    if (![nativeReference isKindOfClass:[NSString class]] || nativeReference.length == 0
        || nativeReference.length > 4096 || containsNul(nativeReference)
        || !titles || titles.count == 0) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSDictionary *preflight = writePreflightFailure(requestID, nativeReference);
    if (preflight) return preflight;
    NSDictionary *snapshot = nil;
    return mutationResponse(
        requestID, ensureSubtasks(nativeReference, titles, &snapshot), snapshot);
}

static NSDictionary *addImageAttachmentResponse(NSString *requestID, NSDictionary *payload,
                                                NSDictionary *policy) {
    if (!dictionaryHasExactlyKeys(payload, @[@"native_locator", @"filename"])) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSString *nativeReference = payload[@"native_locator"];
    NSString *filename = payload[@"filename"];
    id artifactDirectory = policy[@"artifact_directory"];
    if (![nativeReference isKindOfClass:[NSString class]] || nativeReference.length == 0
        || nativeReference.length > 4096 || containsNul(nativeReference)) {
        return failure(requestID, @"protocol.invalid_payload");
    }
    NSURL *artifactURL = validatedArtifactURL(artifactDirectory, filename);
    if (!artifactURL) return failure(requestID, @"private.invalid_artifact");
    NSDictionary *preflight = writePreflightFailure(requestID, nativeReference);
    if (preflight) return preflight;
    NSDictionary *snapshot = nil;
    return mutationResponse(requestID,
        addImageAttachment(nativeReference, artifactURL, filename, &snapshot), snapshot);
}

static NSDictionary *handleRequest(NSDictionary *request) {
    NSSet *expectedKeys = [NSSet setWithArray:@[
        @"kind", @"protocol_version", @"application_contract", @"request_id", @"operation_id", @"capability",
        @"payload", @"deadline_ms", @"idempotency_key", @"policy",
    ]];
    NSString *requestID = safeIdentifier(request[@"request_id"])
        ? request[@"request_id"] : @"unknown";
    if (![[NSSet setWithArray:request.allKeys] isEqualToSet:expectedKeys]
        || ![request[@"kind"] isEqual:@"request"]
        || ![request[@"protocol_version"] isEqual:ProtocolVersion]
        || ![request[@"application_contract"] isEqual:ApplicationContract]
        || !safeIdentifier(requestID)
        || !safeIdentifier(request[@"operation_id"])
        || !safeIdentifier(request[@"capability"])
        || !safeIdentifier(request[@"idempotency_key"])
        || ![request[@"payload"] isKindOfClass:[NSDictionary class]]
        || ![request[@"policy"] isKindOfClass:[NSDictionary class]]
        || ![request[@"deadline_ms"] isKindOfClass:[NSNumber class]]
        || isBoolean(request[@"deadline_ms"])
        || [request[@"deadline_ms"] unsignedLongLongValue] == 0
        || [request[@"deadline_ms"] unsignedLongLongValue] > 300000) {
        return failure(requestID, @"protocol.invalid_envelope");
    }
    NSString *capabilityName = request[@"capability"];
    CurrentOperationID = request[@"operation_id"];
    CurrentCapability = capabilityName;
    NSDictionary *payload = request[@"payload"];
    NSDictionary *policy = request[@"policy"];
    BOOL isWrite = [capabilityName isEqual:@"reminder.private.authorization.request"]
        || [capabilityName isEqual:@"reminder.private.tags.replace"]
        || [capabilityName isEqual:@"reminder.private.flagged.set"]
        || [capabilityName isEqual:@"reminder.private.url_attachments.replace"]
        || [capabilityName isEqual:@"reminder.private.section.assign"]
        || [capabilityName isEqual:@"reminder.private.subtasks.ensure"]
        || [capabilityName isEqual:@"reminder.private.image_attachment.add"];
    BOOL allowsArtifact = [capabilityName
        isEqual:@"reminder.private.image_attachment.add"];
    NSString *effect = isWrite ? ([capabilityName isEqual:@"reminder.private.authorization.request"] ? @"authorization_prompt" : @"mutation") : @"read";
    NSString *evidence = isWrite ? ([capabilityName isEqual:@"reminder.private.authorization.request"] ? @"authorization_readback" : @"native_readback") : @"none";
    if (!validPolicy(policy, effect, evidence, allowsArtifact)) {
        return failure(requestID, @"protocol.invalid_envelope");
    }

    if ([capabilityName isEqual:@"reminder.private.authorization.status"]) {
        if (payload.count != 0) return failure(requestID, @"protocol.invalid_payload");
        return authorizationStatus(requestID);
    }
    if ([capabilityName isEqual:@"reminder.private.authorization.request"]) {
        if (payload.count != 0) return failure(requestID, @"protocol.invalid_payload");
        if (!environmentEnabled(@"SHERPA_ALLOW_PERMISSION_PROMPT")) {
            return failureWithRetry(
                requestID, @"private.permission_prompt_disabled", @"after_user_action");
        }
        return requestAuthorization(requestID);
    }

    if (![capabilityName isEqual:@"capabilities"]
        && ![capabilityName isEqual:@"reminder.private.snapshot"]
        && ![capabilityName isEqual:@"reminder.private.snapshots"]
        && ![capabilityName isEqual:@"reminder.private.sections.collection"]
        && ![capabilityName isEqual:@"reminder.private.tags.replace"]
        && ![capabilityName isEqual:@"reminder.private.flagged.set"]
        && ![capabilityName isEqual:@"reminder.private.url_attachments.replace"]
        && ![capabilityName isEqual:@"reminder.private.section.assign"]
        && ![capabilityName isEqual:@"reminder.private.subtasks.ensure"]
        && ![capabilityName isEqual:@"reminder.private.image_attachment.add"]) {
        return failure(requestID, @"protocol.unsupported_capability");
    }
    BOOL loaded = loadPrivateFrameworks();
    NSArray *report = probeCapabilities(loaded);
    if ([capabilityName isEqual:@"reminder.private.snapshot"]) {
        if (!loaded) return failure(requestID, @"private.framework_unavailable");
        return snapshotResponse(requestID, payload);
    }
    if ([capabilityName isEqual:@"reminder.private.snapshots"]) {
        if (!loaded) return failure(requestID, @"private.framework_unavailable");
        return snapshotsResponse(requestID, payload);
    }
    if ([capabilityName isEqual:@"reminder.private.sections.collection"]) {
        if (!loaded) return failure(requestID, @"private.framework_unavailable");
        return sectionsResponse(requestID, payload);
    }
    if ([capabilityName isEqual:@"reminder.private.tags.replace"]) {
        if (!loaded) return failure(requestID, @"private.framework_unavailable");
        return replaceTagsResponse(requestID, payload);
    }
    if ([capabilityName isEqual:@"reminder.private.flagged.set"]) {
        if (!loaded) return failure(requestID, @"private.framework_unavailable");
        return setFlaggedResponse(requestID, payload);
    }
    if ([capabilityName isEqual:@"reminder.private.url_attachments.replace"]) {
        if (!loaded) return failure(requestID, @"private.framework_unavailable");
        return replaceURLAttachmentsResponse(requestID, payload);
    }
    if ([capabilityName isEqual:@"reminder.private.section.assign"]) {
        if (!loaded) return failure(requestID, @"private.framework_unavailable");
        return assignSectionResponse(requestID, payload);
    }
    if ([capabilityName isEqual:@"reminder.private.subtasks.ensure"]) {
        if (!loaded) return failure(requestID, @"private.framework_unavailable");
        return ensureSubtasksResponse(requestID, payload);
    }
    if ([capabilityName isEqual:@"reminder.private.image_attachment.add"]) {
        if (!loaded) return failure(requestID, @"private.framework_unavailable");
        return addImageAttachmentResponse(requestID, payload, policy);
    }
    if (payload.count != 0) return failure(requestID, @"protocol.invalid_payload");
    NSDictionary *result = @{
        @"schema": @"sherpa.worker-capabilities.v2",
        @"capabilities": report,
    };
    return @{
        @"kind": @"response",
        @"protocol_version": ProtocolVersion,
        @"application_contract": ApplicationContract,
        @"request_id": requestID,
        @"operation_id": CurrentOperationID,
        @"capability": CurrentCapability,
        @"status": @"succeeded",
        @"result": result,
        @"effect": @{ @"kind": @"none", @"state": @"not_applicable" },
        @"evidence": [NSNull null],
        @"error": [NSNull null],
        @"warnings": @[],
    };
}

NSData *SherpaReminderKitHandleRequest(NSData *input) {
    @autoreleasepool {
        static const NSUInteger MaxRequestBytes = 64 * 1024;
        if (input.length > MaxRequestBytes) {
            return responseData(failure(@"unknown", @"protocol.request_too_large"));
        }
        if (input.length == 0) {
            return responseData(failure(@"unknown", @"protocol.invalid_envelope"));
        }
        NSError *error = nil;
        id object = [NSJSONSerialization JSONObjectWithData:input options:0 error:&error];
        if (error || ![object isKindOfClass:[NSDictionary class]]) {
            return responseData(failure(@"unknown", @"protocol.invalid_json"));
        }
        NSString *requestID = safeIdentifier(object[@"request_id"])
            ? object[@"request_id"] : @"unknown";
        NSString *capabilityName = safeIdentifier(object[@"capability"])
            ? object[@"capability"] : @"unknown";
        workerLog(@"info", @"start", capabilityName, nil);
        @try {
            NSDictionary *response = handleRequest(object);
            if ([response[@"status"] isEqual:@"succeeded"]) {
                workerLog(@"info", @"success", capabilityName, nil);
            } else {
                workerLog(@"error", @"failure", capabilityName,
                          [response[@"error"] isKindOfClass:[NSDictionary class]]
                              ? response[@"error"][@"code"] : @"protocol.missing_error");
            }
            return responseData(response);
        } @catch (__unused NSException *exception) {
            workerLog(@"error", @"failure", capabilityName,
                      @"private.operation_failed");
            return responseData(failure(requestID, @"private.operation_failed"));
        }
    }
}

#ifndef SHERPA_REMINDER_KIT_LIBRARY
int main(void) {
    @autoreleasepool {
        static const NSUInteger MaxRequestBytes = 64 * 1024;
        NSData *input = [[NSFileHandle fileHandleWithStandardInput]
            readDataOfLength:MaxRequestBytes + 1];
        NSData *output = SherpaReminderKitHandleRequest(input);
        if (!output) return EXIT_FAILURE;
        [[NSFileHandle fileHandleWithStandardOutput] writeData:output];
        return EXIT_SUCCESS;
    }
}
#endif
