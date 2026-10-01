public with sharing class ActivityEmailHelper {
    public static Boolean isEmail(Task t) {
        return ActivityApexConstants.EMAIL_SUBTYPES.contains(t.TaskSubtype);
    }
    public static void sendEmail(Id recordId, String toAddresses, String ccAddresses, String subject, String htmlBody) {
        ActivityUtilityClass.requireRecordId(recordId);
        List<String> toList = ActivityUtilityClass.splitAddresses(toAddresses);
        List<String> ccList = ActivityUtilityClass.splitAddresses(ccAddresses);
        if (toList.isEmpty()) {
            throw ActivityUtilityClass.newAuraException(ActivityApexConstants.ERR_RECIPIENT_REQUIRED);
        }
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toList);
            if (!ccList.isEmpty()) {
                mail.setCcAddresses(ccList);
            }
            mail.setSubject(subject == null ? '' : subject);
            mail.setHtmlBody(htmlBody == null ? '' : htmlBody);
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            throw ActivityUtilityClass.newAuraException(ActivityApexConstants.ERR_EMAIL_NOT_SENT + e.getMessage());
        }
        insertEmailTask(recordId, toList, ccList, subject, htmlBody, Date.today());
    }

    public static void logEmail(Id recordId, String toAddresses, String subject, String htmlBody, Date emailDate) {
        ActivityUtilityClass.requireRecordId(recordId);
        insertEmailTask(
            recordId,
            ActivityUtilityClass.splitAddresses(toAddresses),
            new List<String>(),
            subject,
            htmlBody,
            emailDate == null ? Date.today() : emailDate
        );
    }


    private static void insertEmailTask(
        Id recordId,
        List<String> toList,
        List<String> ccList,
        String subject,
        String htmlBody,
        Date emailDate
    ) {
        String emailSubject = String.isBlank(subject) ? ActivityApexConstants.NO_SUBJECT : subject;
        Task t = new Task(
            Subject = (ActivityApexConstants.EMAIL_SUBJECT_PREFIX + emailSubject)
                .abbreviate(ActivityApexConstants.SUBJECT_MAX_LENGTH),
            TaskSubtype = ActivityApexConstants.SUBTYPE_EMAIL,
            Status = ActivityUtilityClass.getTaskStatus(true),
            ActivityDate = emailDate,
            OwnerId = UserInfo.getUserId(),
            Description = buildDescription(toList, ccList, htmlBody)
                .abbreviate(ActivityApexConstants.DESCRIPTION_MAX_LENGTH)
        );

        if (ActivityUtilityClass.isWhoType(recordId.getSObjectType())) {
            t.WhoId = recordId;
        } else {
            t.WhatId = recordId;
            t.WhoId = ActivityUtilityClass.findContactByEmail(toList);
        }
        insert as user t;
    }

    private static String buildDescription(List<String> toList, List<String> ccList, String htmlBody) {
        String newLine = ActivityApexConstants.NEW_LINE;
        String description = '';
        if (!toList.isEmpty()) {
            description +=
                ActivityApexConstants.TO_LABEL + String.join(toList, ActivityApexConstants.ADDRESS_SEPARATOR) + newLine;
        }
        if (!ccList.isEmpty()) {
            description +=
                ActivityApexConstants.CC_LABEL + String.join(ccList, ActivityApexConstants.ADDRESS_SEPARATOR) + newLine;
        }
        String body = String.isBlank(htmlBody)
            ? ''
            : htmlBody.replaceAll(ActivityApexConstants.HTML_BREAK_REGEX, newLine).stripHtmlTags();
        return (description + newLine + body).trim();
    }
}