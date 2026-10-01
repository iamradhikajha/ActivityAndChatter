public with sharing class ActivityTimelineController {

    public class ActivityItem {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String subject;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String priority;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Date activityDate;
        @AuraEnabled
        public Date effectiveDate;
        @AuraEnabled
        public Boolean isClosed;
        @AuraEnabled
        public Boolean isOverdue;
        @AuraEnabled
        public Boolean isMine;
        @AuraEnabled
        public Id ownerId;
        @AuraEnabled
        public String ownerName;
        @AuraEnabled
        public Id whoId;
        @AuraEnabled
        public String whoName;
        @AuraEnabled
        public Id whatId;
        @AuraEnabled
        public String whatName;
    }

    public class TimelineData {
        @AuraEnabled
        public List<ActivityItem> upcoming = new List<ActivityItem>();
        @AuraEnabled
        public List<ActivityItem> past = new List<ActivityItem>();
        @AuraEnabled
        public Boolean hasMorePast = false;
    }

    public class RecordContext {
        @AuraEnabled
        public String objectApiName;
        @AuraEnabled
        public Boolean isWhoRecord;
        @AuraEnabled
        public Boolean canRelateWhat;
        @AuraEnabled
        public String defaultEmail;
        @AuraEnabled
        public String openStatus;
        @AuraEnabled
        public String closedStatus;
        @AuraEnabled
        public Id currentUserId;
    }


    @AuraEnabled
    public static TimelineData getActivities(
        Id recordId,
        String dateRange,
        String ownerFilter,
        String typeFilter,
        Boolean viewAll
    ) {
        try {
            return ActivityTaskHelper.getTimeline(recordId, dateRange, ownerFilter, typeFilter, viewAll);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void setTaskCompleted(Id taskId, Boolean completed) {
        try {
            ActivityTaskHelper.setCompleted(taskId, completed);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }


    @AuraEnabled
    public static void sendEmail(
        Id recordId,
        String toAddresses,
        String ccAddresses,
        String subject,
        String htmlBody
    ) {
        try {
            ActivityEmailHelper.sendEmail(recordId, toAddresses, ccAddresses, subject, htmlBody);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void logEmail(Id recordId, String toAddresses, String subject, String htmlBody, Date emailDate) {
        try {
            ActivityEmailHelper.logEmail(recordId, toAddresses, subject, htmlBody, emailDate);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }


    @AuraEnabled(cacheable=true)
    public static RecordContext getRecordContext(Id recordId) {
        try {
            return ActivityUtilityClass.buildRecordContext(recordId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    private static AuraHandledException toAuraException(Exception e) {
        String message = e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage();
        return ActivityUtilityClass.newAuraException(message);
    }
}