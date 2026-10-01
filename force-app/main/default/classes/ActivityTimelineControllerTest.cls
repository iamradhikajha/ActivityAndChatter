@IsTest
private class ActivityTimelineControllerTest {
    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Timeline Co');
        insert acc;
        Contact con = new Contact(LastName = 'Kumari', Email = 'kumari@example.com', AccountId = acc.Id);
        insert con;

        insert new List<Task>{
            new Task(
                Subject = 'Upcoming task',
                WhatId = acc.Id,
                WhoId = con.Id,
                ActivityDate = Date.today().addDays(3),
                Status = 'Not Started'
            ),
            new Task(
                Subject = 'Overdue task',
                WhatId = acc.Id,
                ActivityDate = Date.today().addDays(-3),
                Status = 'Not Started'
            ),
            new Task(
                Subject = 'Done task',
                WhatId = acc.Id,
                ActivityDate = Date.today().addDays(-1),
                Status = 'Completed'
            ),
            new Task(
                Subject = 'Email: Hello',
                WhatId = acc.Id,
                TaskSubtype = 'Email',
                ActivityDate = Date.today(),
                Status = 'Completed'
            ),
            new Task(
                Subject = 'Call',
                WhatId = acc.Id,
                TaskSubtype = 'Call',
                ActivityDate = Date.today(),
                Status = 'Completed'
            )
        };
    }

    private static Account getAccount() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    @IsTest
    static void returnsTasksAndEmailsOnly() {
        Test.startTest();
        ActivityTimelineController.TimelineData data = ActivityTimelineController.getActivities(
            getAccount().Id,
            'all',
            'all',
            'all',
            false
        );
        Test.stopTest();

        Assert.areEqual(2, data.upcoming.size(), 'Two open tasks expected');
        Assert.areEqual(2, data.past.size(), 'Calls must be excluded from the past list');
        Assert.areEqual('Overdue task', data.upcoming[0].subject, 'Overdue task sorts first');
        Assert.isTrue(data.upcoming[0].isOverdue, 'Task should be flagged overdue');
    }

    @IsTest
    static void appliesTypeDateAndOwnerFilters() {
        Id accId = getAccount().Id;
        Test.startTest();
        ActivityTimelineController.TimelineData emails = ActivityTimelineController.getActivities(
            accId,
            'all',
            'all',
            'Email',
            true
        );
        ActivityTimelineController.TimelineData tasks = ActivityTimelineController.getActivities(
            accId,
            'next7',
            'mine',
            'Task',
            false
        );
        ActivityTimelineController.TimelineData last7 = ActivityTimelineController.getActivities(
            accId,
            'last7',
            'all',
            'all',
            false
        );
        ActivityTimelineController.TimelineData last30 = ActivityTimelineController.getActivities(
            accId,
            'last30',
            'all',
            'all',
            false
        );
        Test.stopTest();

        Assert.areEqual(0, emails.upcoming.size(), 'No open emails');
        Assert.areEqual(1, emails.past.size(), 'One logged email');
        Assert.areEqual('Email', emails.past[0].type, 'Type should be Email');
        Assert.areEqual(1, tasks.upcoming.size(), 'Only the upcoming task falls in the next 7 days');
        Assert.areEqual(1, last7.upcoming.size(), 'Only the overdue task falls in the last 7 days');
        Assert.areEqual(2, last30.past.size(), 'Both closed items fall in the last 30 days');
    }

    @IsTest
    static void completesAndReopensTask() {
        Task t = [SELECT Id FROM Task WHERE Subject = 'Upcoming task'];
        Test.startTest();
        ActivityTimelineController.setTaskCompleted(t.Id, true);
        Assert.isTrue([SELECT IsClosed FROM Task WHERE Id = :t.Id].IsClosed, 'Task should be closed');
        ActivityTimelineController.setTaskCompleted(t.Id, false);
        Test.stopTest();
        Assert.isFalse([SELECT IsClosed FROM Task WHERE Id = :t.Id].IsClosed, 'Task should be reopened');
    }

    @IsTest
    static void returnsRecordContext() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Test.startTest();
        ActivityTimelineController.RecordContext ctx = ActivityTimelineController.getRecordContext(con.Id);
        Test.stopTest();
        Assert.areEqual('Contact', ctx.objectApiName, 'Object name');
        Assert.isTrue(ctx.isWhoRecord, 'Contact is a Who record');
        Assert.areEqual('kumari@example.com', ctx.defaultEmail, 'Default email from contact');
        Assert.isNotNull(ctx.closedStatus, 'Closed status resolved');
    }

    @IsTest
    static void logsEmailAndLinksContact() {
        Id accId = getAccount().Id;
        Test.startTest();
        ActivityTimelineController.logEmail(accId, 'kumari@example.com', 'Follow up', '<p>Hi<br/>there</p>', null);
        Test.stopTest();

        Task logged = [SELECT TaskSubtype, WhoId, IsClosed, Description FROM Task WHERE Subject = 'Email: Follow up'];
        Assert.areEqual('Email', logged.TaskSubtype, 'Logged as email');
        Assert.areEqual([SELECT Id FROM Contact LIMIT 1].Id, logged.WhoId, 'Linked to matching contact');
        Assert.isTrue(logged.IsClosed, 'Logged email is closed');
        Assert.isTrue(logged.Description.contains('kumari@example.com'), 'Recipients stored');
    }

    @IsTest
    static void sendsEmail() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Test.startTest();
        try {
            ActivityTimelineController.sendEmail(con.Id, 'kumari@example.com', 'cc@example.com', 'Hi', '<p>Body</p>');
            Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE Subject = 'Email: Hi' AND WhoId = :con.Id]);
        } catch (AuraHandledException e) {
            // Email deliverability may be disabled in the test org.
            Assert.isTrue(e.getMessage().startsWith('Email could not be sent'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void rejectsMissingInputs() {
        try {
            ActivityTimelineController.getActivities(null, 'all', 'all', 'all', false);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.areEqual(ActivityApexConstants.ERR_RECORD_ID_REQUIRED, e.getMessage());
        }
        try {
            ActivityTimelineController.sendEmail(getAccount().Id, '', null, 'Hi', 'Body');
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.areEqual(ActivityApexConstants.ERR_RECIPIENT_REQUIRED, e.getMessage());
        }
        try {
            ActivityTimelineController.logEmail(null, 'a@example.com', 'Hi', 'Body', null);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.areEqual(ActivityApexConstants.ERR_RECORD_ID_REQUIRED, e.getMessage());
        }
        try {
            ActivityTimelineController.getRecordContext(null);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.areEqual(ActivityApexConstants.ERR_RECORD_ID_REQUIRED, e.getMessage());
        }
    }

    @IsTest
    static void surfacesDmlErrors() {
        Task t = [SELECT Id FROM Task WHERE Subject = 'Upcoming task'];
        delete t;
        try {
            ActivityTimelineController.setTaskCompleted(t.Id, true);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(String.isNotBlank(e.getMessage()), 'DML error message returned');
        }
    }


    @IsTest
    static void utilitySplitsAddresses() {
        List<String> parts = ActivityUtilityClass.splitAddresses(' a@x.com, b@y.com;c@z.com  d@w.com ');
        Assert.areEqual(new List<String>{ 'a@x.com', 'b@y.com', 'c@z.com', 'd@w.com' }, parts, 'Split on , ; space');
        Assert.isTrue(ActivityUtilityClass.splitAddresses(null).isEmpty(), 'Null gives empty list');
        Assert.isTrue(ActivityUtilityClass.splitAddresses('  ').isEmpty(), 'Blank gives empty list');
    }

    @IsTest
    static void utilityResolvesRecordTypesAndStatuses() {
        Assert.isTrue(ActivityUtilityClass.isWhoType(Contact.SObjectType), 'Contact is Who');
        Assert.isTrue(ActivityUtilityClass.isWhoType(Lead.SObjectType), 'Lead is Who');
        Assert.isFalse(ActivityUtilityClass.isWhoType(Account.SObjectType), 'Account is What');

        String closed = ActivityUtilityClass.getTaskStatus(true);
        String open = ActivityUtilityClass.getTaskStatus(false);
        Assert.isTrue(
            [SELECT IsClosed FROM TaskStatus WHERE ApiName = :closed LIMIT 1].IsClosed,
            'Closed status is closed'
        );
        Assert.isFalse([SELECT IsClosed FROM TaskStatus WHERE ApiName = :open LIMIT 1].IsClosed, 'Open status is open');
    }

    @IsTest
    static void utilityFindsContactByEmail() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Assert.areEqual(
            con.Id,
            ActivityUtilityClass.findContactByEmail(new List<String>{ 'nobody@example.com', 'kumari@example.com' }),
            'Matching contact'
        );
        Assert.isNull(ActivityUtilityClass.findContactByEmail(new List<String>{ 'nobody@example.com' }), 'No match');
        Assert.isNull(ActivityUtilityClass.findContactByEmail(new List<String>()), 'Empty list');
    }

    @IsTest
    static void utilityBuildsLeadAndAccountContext() {
        Lead ld = new Lead(LastName = 'Lead', Company = 'Acme', Email = 'lead@example.com');
        insert ld;
        ActivityTimelineController.RecordContext leadCtx = ActivityUtilityClass.buildRecordContext(ld.Id);
        Assert.isTrue(leadCtx.isWhoRecord, 'Lead is Who');
        Assert.isFalse(leadCtx.canRelateWhat, 'Lead tasks cannot have Related To');
        Assert.areEqual('lead@example.com', leadCtx.defaultEmail, 'Lead email');

        ActivityTimelineController.RecordContext accCtx = ActivityUtilityClass.buildRecordContext(getAccount().Id);
        Assert.isFalse(accCtx.isWhoRecord, 'Account is What');
        Assert.isTrue(accCtx.canRelateWhat, 'Account can be Related To');
        Assert.isNull(accCtx.defaultEmail, 'No default email for Account');
    }


    @IsTest
    static void taskHelperPagesPastActivity() {
        Id accId = getAccount().Id;
        List<Task> done = new List<Task>();
        for (Integer i = 0; i < ActivityApexConstants.DEFAULT_PAST_LIMIT + 2; i++) {
            done.add(new Task(Subject = 'Old ' + i, WhatId = accId, Status = ActivityUtilityClass.getTaskStatus(true)));
        }
        insert done;

        Test.startTest();
        ActivityTimelineController.TimelineData limited = ActivityTaskHelper.getTimeline(
            accId,
            ActivityApexConstants.FILTER_ALL,
            ActivityApexConstants.FILTER_ALL,
            ActivityApexConstants.TYPE_TASK,
            false
        );
        ActivityTimelineController.TimelineData all = ActivityTaskHelper.getTimeline(
            accId,
            ActivityApexConstants.FILTER_ALL,
            ActivityApexConstants.FILTER_ALL,
            ActivityApexConstants.TYPE_TASK,
            true
        );
        Test.stopTest();

        Assert.areEqual(ActivityApexConstants.DEFAULT_PAST_LIMIT, limited.past.size(), 'Past list is capped');
        Assert.isTrue(limited.hasMorePast, 'More past activity flagged');
        Assert.areEqual(ActivityApexConstants.DEFAULT_PAST_LIMIT + 3, all.past.size(), 'View all returns everything');
        Assert.isFalse(all.hasMorePast, 'Nothing more to load');
        Assert.isNotNull(all.past[0].effectiveDate, 'Effective date falls back when ActivityDate is empty');
    }


    @IsTest
    static void emailHelperDetectsEmailSubtypes() {
        Assert.isTrue(ActivityEmailHelper.isEmail(new Task(TaskSubtype = ActivityApexConstants.SUBTYPE_EMAIL)), 'Email');
        Assert.isTrue(
            ActivityEmailHelper.isEmail(new Task(TaskSubtype = ActivityApexConstants.SUBTYPE_LIST_EMAIL)),
            'List email'
        );
        Assert.isFalse(ActivityEmailHelper.isEmail(new Task(TaskSubtype = ActivityApexConstants.SUBTYPE_TASK)), 'Task');
        Assert.isFalse(ActivityEmailHelper.isEmail(new Task()), 'No subtype');
    }

    @IsTest
    static void emailHelperLogsOnWhoRecordWithoutSubject() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Date sentOn = Date.today().addDays(-2);
        Test.startTest();
        ActivityEmailHelper.logEmail(con.Id, '', null, null, sentOn);
        Test.stopTest();

        Task logged = [
            SELECT Subject, WhoId, WhatId, ActivityDate, TaskSubtype
            FROM Task
            WHERE WhoId = :con.Id AND TaskSubtype = :ActivityApexConstants.SUBTYPE_EMAIL
        ];
        Assert.areEqual(
            ActivityApexConstants.EMAIL_SUBJECT_PREFIX + ActivityApexConstants.NO_SUBJECT,
            logged.Subject,
            'Default subject'
        );
        Assert.isNull(logged.WhatId, 'Who record is not set as Related To');
        Assert.areEqual(sentOn, logged.ActivityDate, 'Email date kept');
    }
}