public with sharing class ActivityUtilityClass {
    public static AuraHandledException newAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    public static void requireRecordId(Id recordId) {
        if (recordId == null) {
            throw newAuraException(ActivityApexConstants.ERR_RECORD_ID_REQUIRED);
        }
    }

    public static Boolean isWhoType(Schema.SObjectType sType) {
        return sType == Contact.SObjectType || sType == Lead.SObjectType;
    }

    public static String getTaskStatus(Boolean closed) {
        List<TaskStatus> statuses = [
            SELECT ApiName
            FROM TaskStatus
            WHERE IsClosed = :closed
            ORDER BY IsDefault DESC, SortOrder ASC
            LIMIT 1
        ];
        if (statuses.isEmpty()) {
            return closed ? ActivityApexConstants.STATUS_COMPLETED : ActivityApexConstants.STATUS_NOT_STARTED;
        }
        return statuses[0].ApiName;
    }

    public static List<String> splitAddresses(String value) {
        List<String> result = new List<String>();
        if (String.isBlank(value)) {
            return result;
        }
        for (String part : value.split(ActivityApexConstants.ADDRESS_SPLIT_REGEX)) {
            if (String.isNotBlank(part)) {
                result.add(part.trim());
            }
        }
        return result;
    }

    public static Id findContactByEmail(List<String> emails) {
        if (emails == null || emails.isEmpty()) {
            return null;
        }
        List<Contact> contacts = [SELECT Id FROM Contact WHERE Email IN :emails WITH USER_MODE LIMIT 1];
        return contacts.isEmpty() ? null : contacts[0].Id;
    }

    public static ActivityTimelineController.RecordContext buildRecordContext(Id recordId) {
        requireRecordId(recordId);
        Schema.SObjectType sType = recordId.getSObjectType();
        ActivityTimelineController.RecordContext ctx = new ActivityTimelineController.RecordContext();
        ctx.objectApiName = String.valueOf(sType);
        ctx.isWhoRecord = isWhoType(sType);
        ctx.canRelateWhat = sType != Lead.SObjectType;
        ctx.openStatus = getTaskStatus(false);
        ctx.closedStatus = getTaskStatus(true);
        ctx.currentUserId = UserInfo.getUserId();

        if (sType == Contact.SObjectType) {
            List<Contact> contacts = [SELECT Email FROM Contact WHERE Id = :recordId WITH USER_MODE];
            ctx.defaultEmail = contacts.isEmpty() ? null : contacts[0].Email;
        } else if (sType == Lead.SObjectType) {
            List<Lead> leads = [SELECT Email FROM Lead WHERE Id = :recordId WITH USER_MODE];
            ctx.defaultEmail = leads.isEmpty() ? null : leads[0].Email;
        }
        return ctx;
    }
}