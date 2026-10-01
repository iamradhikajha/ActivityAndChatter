
public with sharing class ActivityTaskHelper {
    private static final String TASK_FIELDS =
        'SELECT Id, Subject, Status, Priority, Description, ActivityDate, CompletedDateTime, ' +
        'CreatedDate, IsClosed, TaskSubtype, OwnerId, Owner.Name, WhoId, Who.Name, WhatId, What.Name ' +
        'FROM Task WHERE ';

    /**
     * Open (Upcoming & Overdue) and closed (past) Tasks/Emails related to the record.
     * @param dateRange   all | last7 | next7 | last30
     * @param ownerFilter all | mine
     * @param typeFilter  all | Task | Email
     * @param viewAll     true returns up to MAX_LIMIT past items instead of DEFAULT_PAST_LIMIT
     */
    public static ActivityTimelineController.TimelineData getTimeline(
        Id recordId,
        String dateRange,
        String ownerFilter,
        String typeFilter,
        Boolean viewAll
    ) {
        ActivityUtilityClass.requireRecordId(recordId);

        Map<String, Object> binds = new Map<String, Object>{ 'recordId' => recordId };
        List<String> conditions = new List<String>{
            '(WhatId = :recordId OR WhoId = :recordId OR AccountId = :recordId)'
        };
        addTypeCondition(typeFilter, conditions, binds);
        addDateCondition(dateRange, conditions, binds);
        if (ownerFilter == ActivityApexConstants.FILTER_MINE) {
            conditions.add('OwnerId = :userId');
            binds.put('userId', UserInfo.getUserId());
        }

        String baseQuery = TASK_FIELDS + String.join(conditions, ' AND ');
        Integer pastLimit = viewAll == true ? ActivityApexConstants.MAX_LIMIT : ActivityApexConstants.DEFAULT_PAST_LIMIT;

        List<Task> openTasks = Database.queryWithBinds(
            baseQuery +
                ' AND IsClosed = false ORDER BY ActivityDate ASC NULLS LAST, CreatedDate ASC LIMIT ' +
                ActivityApexConstants.MAX_LIMIT,
            binds,
            AccessLevel.USER_MODE
        );
        List<Task> closedTasks = Database.queryWithBinds(
            baseQuery +
                ' AND IsClosed = true ORDER BY ActivityDate DESC NULLS LAST, CreatedDate DESC LIMIT ' +
                (pastLimit + 1),
            binds,
            AccessLevel.USER_MODE
        );

        Date today = Date.today();
        ActivityTimelineController.TimelineData data = new ActivityTimelineController.TimelineData();
        for (Task t : openTasks) {
            data.upcoming.add(toItem(t, today));
        }
        for (Integer i = 0; i < closedTasks.size() && i < pastLimit; i++) {
            data.past.add(toItem(closedTasks[i], today));
        }
        data.hasMorePast = closedTasks.size() > pastLimit;
        return data;
    }

    public static void setCompleted(Id taskId, Boolean completed) {
        update as user new Task(Id = taskId, Status = ActivityUtilityClass.getTaskStatus(completed == true));
    }


    private static void addTypeCondition(String typeFilter, List<String> conditions, Map<String, Object> binds) {
        if (typeFilter == ActivityApexConstants.TYPE_TASK) {
            conditions.add('(TaskSubtype = :taskSubtype OR TaskSubtype = null)');
            binds.put('taskSubtype', ActivityApexConstants.SUBTYPE_TASK);
        } else if (typeFilter == ActivityApexConstants.TYPE_EMAIL) {
            conditions.add('TaskSubtype IN :subtypes');
            binds.put('subtypes', ActivityApexConstants.EMAIL_SUBTYPES);
        } else {
            conditions.add('(TaskSubtype IN :subtypes OR TaskSubtype = null)');
            binds.put('subtypes', ActivityApexConstants.ALL_SUBTYPES);
        }
    }

    private static void addDateCondition(String dateRange, List<String> conditions, Map<String, Object> binds) {
        Date today = Date.today();
        Date startDate;
        Date endDate;
        if (dateRange == ActivityApexConstants.RANGE_LAST_7) {
            startDate = today.addDays(-ActivityApexConstants.DAYS_7);
            endDate = today;
        } else if (dateRange == ActivityApexConstants.RANGE_NEXT_7) {
            startDate = today;
            endDate = today.addDays(ActivityApexConstants.DAYS_7);
        } else if (dateRange == ActivityApexConstants.RANGE_LAST_30) {
            startDate = today.addDays(-ActivityApexConstants.DAYS_30);
            endDate = today;
        }
        if (startDate == null) {
            return;
        }
        Time midnight = Time.newInstance(0, 0, 0, 0);
        binds.put('startDate', startDate);
        binds.put('endDate', endDate);
        binds.put('startDt', Datetime.newInstance(startDate, midnight));
        binds.put('endDt', Datetime.newInstance(endDate.addDays(1), midnight));
        conditions.add(
            '((ActivityDate >= :startDate AND ActivityDate <= :endDate) OR ' +
            '(ActivityDate = null AND CreatedDate >= :startDt AND CreatedDate < :endDt))'
        );
    }

    private static ActivityTimelineController.ActivityItem toItem(Task t, Date today) {
        ActivityTimelineController.ActivityItem item = new ActivityTimelineController.ActivityItem();
        item.id = t.Id;
        item.subject = String.isBlank(t.Subject) ? ActivityApexConstants.NO_SUBJECT : t.Subject;
        item.type = ActivityEmailHelper.isEmail(t) ? ActivityApexConstants.TYPE_EMAIL : ActivityApexConstants.TYPE_TASK;
        item.status = t.Status;
        item.priority = t.Priority;
        item.description = t.Description;
        item.activityDate = t.ActivityDate;
        item.effectiveDate = t.ActivityDate != null
            ? t.ActivityDate
            : (t.CompletedDateTime != null ? t.CompletedDateTime.date() : t.CreatedDate.date());
        item.isClosed = t.IsClosed;
        item.isOverdue = !t.IsClosed && t.ActivityDate != null && t.ActivityDate < today;
        item.isMine = t.OwnerId == UserInfo.getUserId();
        item.ownerId = t.OwnerId;
        item.ownerName = t.Owner?.Name;
        item.whoId = t.WhoId;
        item.whoName = t.Who?.Name;
        item.whatId = t.WhatId;
        item.whatName = t.What?.Name;
        return item;
    }
}