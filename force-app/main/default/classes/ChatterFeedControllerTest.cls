// ConnectApi (Chatter in Apex) write methods need SeeAllData=true; read methods are stubbed with setTest*.
@IsTest(SeeAllData=true)
private class ChatterFeedControllerTest {
    private static Account newAccount() {
        Account acc = new Account(Name = 'Chatter Feed Test ' + Crypto.getRandomInteger());
        insert acc;
        return acc;
    }

    @IsTest
    static void postsAndInteracts() {
        Account acc = newAccount();

        Test.startTest();
        ChatterFeedController.postText(acc.Id, 'Hello feed');
        ChatterFeedController.postPoll(acc.Id, 'Which one?', new List<String>{ 'A', 'B', ' ' });
        ChatterFeedController.postQuestion(acc.Id, 'Why?', 'Some details');

        ConnectApi.FeedItemInput textInput = new ConnectApi.FeedItemInput();
        textInput.subjectId = acc.Id;
        textInput.feedElementType = ConnectApi.FeedElementType.FeedItem;
        textInput.body = new ConnectApi.MessageBodyInput();
        ConnectApi.TextSegmentInput segment = new ConnectApi.TextSegmentInput();
        segment.text = 'Interact with me';
        textInput.body.messageSegments = new List<ConnectApi.MessageSegmentInput>{ segment };
        ConnectApi.FeedElement textPost = ConnectApi.ChatterFeeds.postFeedElement(null, textInput);

        ConnectApi.FeedItemInput pollInput = textInput.clone();
        pollInput.capabilities = new ConnectApi.FeedElementCapabilitiesInput();
        pollInput.capabilities.poll = new ConnectApi.PollCapabilityInput();
        pollInput.capabilities.poll.choices = new List<String>{ 'Yes', 'No' };
        ConnectApi.FeedElement pollPost = ConnectApi.ChatterFeeds.postFeedElement(null, pollInput);

        ChatterFeedController.setLike(textPost.id, true);
        ChatterFeedController.postComment(textPost.id, 'Nice');
        ChatterFeedController.votePoll(pollPost.id, pollPost.capabilities.poll.choices[0].id);
        ChatterFeedController.deletePost(pollPost.id);
        Test.stopTest();

        FeedItem saved = [SELECT LikeCount, CommentCount FROM FeedItem WHERE Id = :textPost.id];
        Assert.areEqual(1, saved.CommentCount, 'Comment saved');
        Assert.areEqual(1, saved.LikeCount, 'Like saved');
        Assert.areEqual(0, [SELECT COUNT() FROM FeedItem WHERE Id = :pollPost.id], 'Poll deleted');
        Assert.areEqual(
            4,
            [SELECT COUNT() FROM FeedItem WHERE ParentId = :acc.Id],
            'Text, controller poll, question and direct text posts remain'
        );
    }

    @IsTest
    static void readsFeedWithAllCapabilities() {
        Account acc = newAccount();
        ConnectApi.FeedElementPage page = new ConnectApi.FeedElementPage();
        page.elements = new List<ConnectApi.FeedElement>{ buildFeedItem() };
        page.nextPageToken = 'next';
        ConnectApi.ChatterFeeds.setTestGetFeedElementsFromFeed(
            null,
            ConnectApi.FeedType.Record,
            acc.Id,
            null,
            10,
            ConnectApi.FeedSortOrder.LastModifiedDateDesc,
            page
        );

        Test.startTest();
        ChatterFeedController.FeedPage result = ChatterFeedController.getFeed(
            acc.Id,
            'LastModifiedDateDesc',
            null,
            null
        );
        Test.stopTest();

        Assert.areEqual(1, result.items.size(), 'One post');
        Assert.areEqual('next', result.nextPageToken, 'Page token passed through');
        ChatterFeedController.FeedPost post = result.items[0];
        Assert.areEqual('Radhika', post.actorName, 'Actor');
        Assert.areEqual('https://photo', post.actorPhotoUrl, 'Actor photo');
        Assert.areEqual(2, post.header.size(), 'Header segments');
        Assert.areEqual('record', post.header[0].type, 'Entity link');
        Assert.isTrue(post.isLiked, 'Liked');
        Assert.areEqual(3, post.likeCount, 'Like count');
        Assert.areEqual(1, post.comments.size(), 'Comment');
        Assert.areEqual('Great', post.comments[0].text, 'Comment text');
        Assert.areEqual(5, post.viewCount, 'Views');
        Assert.areEqual('Why?', post.questionTitle, 'Question');
        Assert.areEqual(2, post.poll.choices.size(), 'Poll choices');
        Assert.areEqual('test task', post.record.name, 'Record snapshot');
        Assert.areEqual('Doc', post.files[0].title, 'File');
        Assert.areEqual('Example', post.linkName, 'Link');
        Assert.areEqual('Rating from blank to Hot.', post.changes[0], 'Tracked change');
    }

    @IsTest
    static void searchesFeed() {
        Account acc = newAccount();
        ConnectApi.ChatterFeeds.setTestSearchFeedElementsInFeed(
            null,
            ConnectApi.FeedType.Record,
            acc.Id,
            null,
            10,
            ConnectApi.FeedSortOrder.CreatedDateDesc,
            'Hello',
            new ConnectApi.FeedElementPage()
        );
        Test.startTest();
        ChatterFeedController.FeedPage page = ChatterFeedController.getFeed(acc.Id, 'CreatedDateDesc', 'Hello', null);
        Test.stopTest();
        Assert.areEqual(0, page.items.size(), 'Stubbed search returns nothing');
    }

    @IsTest
    static void convertsMessageSegments() {
        ConnectApi.MessageBody body = new ConnectApi.MessageBody();
        ConnectApi.TextSegment text = new ConnectApi.TextSegment();
        text.text = 'Hi ';
        ConnectApi.LinkSegment link = new ConnectApi.LinkSegment();
        link.text = 'site';
        link.url = 'https://example.com';
        ConnectApi.MentionSegment mention = new ConnectApi.MentionSegment();
        mention.text = '@Kumari';
        mention.record = new ConnectApi.UserSummary();
        mention.record.id = UserInfo.getUserId();
        ConnectApi.MarkupBeginSegment bold = new ConnectApi.MarkupBeginSegment();
        bold.markupType = ConnectApi.MarkupType.Bold;
        ConnectApi.MarkupEndSegment boldEnd = new ConnectApi.MarkupEndSegment();
        boldEnd.markupType = ConnectApi.MarkupType.Bold;
        ConnectApi.MarkupEndSegment paragraphEnd = new ConnectApi.MarkupEndSegment();
        paragraphEnd.markupType = ConnectApi.MarkupType.Paragraph;
        body.messageSegments = new List<ConnectApi.MessageSegment>{ text, link, mention, bold, boldEnd, paragraphEnd };

        List<ChatterFeedController.Segment> segments = ChatterFeedController.toSegments(body);
        Assert.areEqual(4, segments.size(), 'Markup segments are skipped except paragraph ends');
        Assert.areEqual('link', segments[1].type, 'Link segment');
        Assert.areEqual('record', segments[2].type, 'Mention segment');
        Assert.areEqual('\n', segments[3].text, 'Paragraph end becomes a line break');
    }

    @IsTest
    static void rejectsInvalidInput() {
        Account acc = newAccount();
        List<String> errors = new List<String>();
        try {
            ChatterFeedController.postText(acc.Id, ' ');
        } catch (AuraHandledException e) {
            errors.add(e.getMessage());
        }
        try {
            ChatterFeedController.postPoll(acc.Id, 'Q', new List<String>{ 'Only one' });
        } catch (AuraHandledException e) {
            errors.add(e.getMessage());
        }
        try {
            ChatterFeedController.postQuestion(acc.Id, '', null);
        } catch (AuraHandledException e) {
            errors.add(e.getMessage());
        }
        try {
            ChatterFeedController.postComment('0D5000000000000', '');
        } catch (AuraHandledException e) {
            errors.add(e.getMessage());
        }
        try {
            ChatterFeedController.getFeed(null, null, null, null);
        } catch (AuraHandledException e) {
            errors.add(e.getMessage());
        }
        try {
            ChatterFeedController.setLike('bad', true);
        } catch (AuraHandledException e) {
            errors.add(e.getMessage());
        }
        try {
            ChatterFeedController.votePoll('bad', 'bad');
        } catch (AuraHandledException e) {
            errors.add(e.getMessage());
        }
        try {
            ChatterFeedController.deletePost('bad');
        } catch (AuraHandledException e) {
            errors.add(e.getMessage());
        }
        Assert.areEqual(8, errors.size(), 'All invalid inputs rejected: ' + errors);
    }


    private static ConnectApi.FeedItem buildFeedItem() {
        ConnectApi.FeedItem item = new ConnectApi.FeedItem();
        item.id = '0D5000000000001';
        item.relativeCreatedDate = '2h ago';
        item.isDeleteRestricted = false;

        ConnectApi.UserSummary actor = new ConnectApi.UserSummary();
        actor.id = UserInfo.getUserId();
        actor.name = 'Radhika';
        actor.displayName = 'Radhika';
        actor.photo = new ConnectApi.Photo();
        actor.photo.smallPhotoUrl = 'https://photo';
        item.actor = actor;

        ConnectApi.EntityLinkSegment taskLink = new ConnectApi.EntityLinkSegment();
        taskLink.text = 'test task';
        taskLink.reference = new ConnectApi.Reference();
        taskLink.reference.id = '00T000000000001';
        ConnectApi.TextSegment createdText = new ConnectApi.TextSegment();
        createdText.text = ' created a task.';
        item.header = new ConnectApi.MessageBody();
        item.header.messageSegments = new List<ConnectApi.MessageSegment>{ taskLink, createdText };

        ConnectApi.TextSegment bodyText = new ConnectApi.TextSegment();
        bodyText.text = 'Body';
        item.body = new ConnectApi.FeedBody();
        item.body.messageSegments = new List<ConnectApi.MessageSegment>{ bodyText };

        ConnectApi.FeedElementCapabilities caps = new ConnectApi.FeedElementCapabilities();

        caps.chatterLikes = new ConnectApi.ChatterLikesCapability();
        caps.chatterLikes.isLikedByCurrentUser = true;
        caps.chatterLikes.page = new ConnectApi.ChatterLikePage();
        caps.chatterLikes.page.total = 3;

        ConnectApi.Comment comment = new ConnectApi.Comment();
        comment.id = '0D7000000000001';
        comment.relativeCreatedDate = '1h ago';
        comment.body = new ConnectApi.FeedBody();
        comment.body.text = 'Great';
        comment.user = actor;
        caps.comments = new ConnectApi.CommentsCapability();
        caps.comments.page = new ConnectApi.CommentPage();
        caps.comments.page.total = 1;
        caps.comments.page.items = new List<ConnectApi.Comment>{ comment };

        caps.interactions = new ConnectApi.InteractionsCapability();
        caps.interactions.count = 5;

        caps.questionAndAnswers = new ConnectApi.QuestionAndAnswersCapability();
        caps.questionAndAnswers.questionTitle = 'Why?';

        ConnectApi.FeedPollChoice yes = new ConnectApi.FeedPollChoice();
        yes.id = '09A000000000001';
        yes.text = 'Yes';
        yes.voteCount = 2;
        ConnectApi.FeedPollChoice no = new ConnectApi.FeedPollChoice();
        no.id = '09A000000000002';
        no.text = 'No';
        no.voteCount = 1;
        caps.poll = new ConnectApi.PollCapability();
        caps.poll.choices = new List<ConnectApi.FeedPollChoice>{ yes, no };
        caps.poll.myChoiceId = yes.id;
        caps.poll.totalVoteCount = 3;

        ConnectApi.RecordView view = new ConnectApi.RecordView();
        view.id = '00T000000000001';
        view.name = 'test task';
        view.type = 'Task';
        caps.recordSnapshot = new ConnectApi.RecordSnapshotCapability();
        caps.recordSnapshot.recordView = view;

        ConnectApi.Content file = new ConnectApi.Content();
        file.id = '069000000000001';
        file.title = 'Doc';
        caps.files = new ConnectApi.FilesCapability();
        caps.files.items = new List<ConnectApi.Content>{ file };

        caps.link = new ConnectApi.LinkCapability();
        caps.link.url = 'https://example.com';
        caps.link.urlName = 'Example';

        ConnectApi.TrackedChangeItem change = new ConnectApi.TrackedChangeItem();
        change.fieldName = 'Rating';
        change.newValue = 'Hot';
        caps.trackedChanges = new ConnectApi.TrackedChangesCapability();
        caps.trackedChanges.changes = new List<ConnectApi.TrackedChangeItem>{ change };

        item.capabilities = caps;
        return item;
    }
}