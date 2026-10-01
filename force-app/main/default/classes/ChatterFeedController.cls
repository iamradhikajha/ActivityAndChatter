public with sharing class ChatterFeedController {
    private static final Integer PAGE_SIZE = 10;

    public class FeedPage { @AuraEnabled public List<FeedPost> items = new List<FeedPost>();
         @AuraEnabled 
         public String nextPageToken; 
         @AuraEnabled public String currentUserPhotoUrl;
        }

    public class Segment {
        @AuraEnabled
        public String type;
        @AuraEnabled
        public String text;
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String url;
    }

    public class FeedPost {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String actorId;
        @AuraEnabled
        public String actorName;
        @AuraEnabled
        public String actorPhotoUrl;
        @AuraEnabled
        public String relativeDate;
        @AuraEnabled
        public List<Segment> header = new List<Segment>();
        @AuraEnabled
        public List<Segment> body = new List<Segment>();
        @AuraEnabled
        public Boolean canDelete = false;
        @AuraEnabled
        public Boolean isLiked = false;
        @AuraEnabled
        public Integer likeCount = 0;
        @AuraEnabled
        public Integer commentCount = 0;
        @AuraEnabled
        public List<FeedCommentItem> comments = new List<FeedCommentItem>();
        @AuraEnabled
        public Integer viewCount = 0;
        @AuraEnabled
        public String questionTitle;
        @AuraEnabled
        public PollInfo poll;
        @AuraEnabled
        public RecordCard record;
        @AuraEnabled
        public List<FileInfo> files = new List<FileInfo>();
        @AuraEnabled
        public String linkUrl;
        @AuraEnabled
        public String linkName;
        @AuraEnabled
        public List<String> changes = new List<String>();
    }

    public class FeedCommentItem {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String userId;
        @AuraEnabled
        public String userName;
        @AuraEnabled
        public String userPhotoUrl;
        @AuraEnabled
        public String text;
        @AuraEnabled
        public String relativeDate;
    }

    public class PollInfo {
        @AuraEnabled
        public List<PollChoice> choices = new List<PollChoice>();
        @AuraEnabled
        public String myChoiceId;
        @AuraEnabled
        public Integer totalVotes = 0;
    }

    public class PollChoice {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String text;
        @AuraEnabled
        public Integer voteCount = 0;
    }

    public class RecordCard {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String type;
    }

    public class FileInfo {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String title;
    }


    /**
     * @param sortOrder   teDesc (Most Recent Activity)
     * @param searchTerm  optional; searches within this record's feed
     * @param pageToken   next page token from a previous call, or null for the first page
     */
    @AuraEnabled
    public static FeedPage getFeed(Id recordId, String sortOrder, String searchTerm, String pageToken) {
        if (recordId == null) {
            throw newAuraException('A record Id is required.');
        }
        try {
            ConnectApi.FeedSortOrder sortParam = sortOrder == 'LastModifiedDateDesc'
                ? ConnectApi.FeedSortOrder.LastModifiedDateDesc
                : ConnectApi.FeedSortOrder.CreatedDateDesc;

            ConnectApi.FeedElementPage page;
            if (String.isNotBlank(searchTerm)) {
                page = ConnectApi.ChatterFeeds.searchFeedElementsInFeed(
                    null,
                    ConnectApi.FeedType.Record,
                    recordId,
                    pageToken,
                    PAGE_SIZE,
                    sortParam,
                    searchTerm.trim()
                );
            } else {
                page = ConnectApi.ChatterFeeds.getFeedElementsFromFeed(
                    null,
                    ConnectApi.FeedType.Record,
                    recordId,
                    pageToken,
                    PAGE_SIZE,
                    sortParam
                );
            }

            FeedPage result = new FeedPage();
            result.currentUserPhotoUrl = [SELECT SmallPhotoUrl FROM User WHERE Id = :UserInfo.getUserId()]
            .SmallPhotoUrl;
            if (page != null && page.elements != null) {
                for (ConnectApi.FeedElement element : page.elements) {
                    result.items.add(toPost(element));
                }
                result.nextPageToken = page.nextPageToken;
            }
            return result;
        } catch (Exception e) {
            throw newAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void postText(Id recordId, String text) {
        if (String.isBlank(text)) {
            throw newAuraException('Write something to share.');
        }
        post(buildInput(recordId, text));
    }

    @AuraEnabled
    public static void postPoll(Id recordId, String question, List<String> choices) {
        List<String> cleaned = new List<String>();
        for (String choice : choices == null ? new List<String>() : choices) {
            if (String.isNotBlank(choice)) {
                cleaned.add(choice.trim());
            }
        }
        if (String.isBlank(question) || cleaned.size() < 2) {
            throw newAuraException('A poll needs a question and at least two choices.');
        }
        ConnectApi.FeedItemInput input = buildInput(recordId, question);
        ConnectApi.PollCapabilityInput poll = new ConnectApi.PollCapabilityInput();
        poll.choices = cleaned;
        input.capabilities = new ConnectApi.FeedElementCapabilitiesInput();
        input.capabilities.poll = poll;
        post(input);
    }

    @AuraEnabled
    public static void postQuestion(Id recordId, String title, String details) {
        if (String.isBlank(title)) {
            throw newAuraException('Enter a question.');
        }
        ConnectApi.FeedItemInput input = buildInput(recordId, details);
        ConnectApi.QuestionAndAnswersCapabilityInput qa = new ConnectApi.QuestionAndAnswersCapabilityInput();
        qa.questionTitle = title.trim();
        input.capabilities = new ConnectApi.FeedElementCapabilitiesInput();
        input.capabilities.questionAndAnswers = qa;
        post(input);
    }

    @AuraEnabled
    public static void setLike(String feedElementId, Boolean liked) {
        try {
            ConnectApi.ChatterFeeds.updateLikeForFeedElement(null, feedElementId, liked == true);
        } catch (Exception e) {
            throw newAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void postComment(String feedElementId, String text) {
        if (String.isBlank(text)) {
            throw newAuraException('Write a comment first.');
        }
        try {
            ConnectApi.ChatterFeeds.postCommentToFeedElement(null, feedElementId, text.trim());
        } catch (Exception e) {
            throw newAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void votePoll(String feedElementId, String choiceId) {
        try {
            ConnectApi.ChatterFeeds.voteOnFeedElementPoll(null, feedElementId, choiceId);
        } catch (Exception e) {
            throw newAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void deletePost(String feedElementId) {
        try {
            ConnectApi.ChatterFeeds.deleteFeedElement(null, feedElementId);
        } catch (Exception e) {
            throw newAuraException(e.getMessage());
        }
    }

    private static ConnectApi.FeedItemInput buildInput(Id recordId, String text) {
        ConnectApi.FeedItemInput input = new ConnectApi.FeedItemInput();
        input.subjectId = recordId;
        input.feedElementType = ConnectApi.FeedElementType.FeedItem;
        ConnectApi.MessageBodyInput body = new ConnectApi.MessageBodyInput();
        body.messageSegments = new List<ConnectApi.MessageSegmentInput>();
        if (String.isNotBlank(text)) {
            ConnectApi.TextSegmentInput segment = new ConnectApi.TextSegmentInput();
            segment.text = text.trim();
            body.messageSegments.add(segment);
        }
        input.body = body;
        return input;
    }

    private static void post(ConnectApi.FeedItemInput input) {
        try {
            ConnectApi.ChatterFeeds.postFeedElement(null, input);
        } catch (Exception e) {
            throw newAuraException(e.getMessage());
        }
    }

    @TestVisible
    private static FeedPost toPost(ConnectApi.FeedElement element) {
        FeedPost p = new FeedPost();
        p.id = element.id;
        p.relativeDate = element.relativeCreatedDate;
        p.header = toSegments(element.header);
        p.body = toSegments(element.body);

        if (element instanceof ConnectApi.FeedItem) {
            ConnectApi.FeedItem item = (ConnectApi.FeedItem) element;
            p.canDelete = item.isDeleteRestricted != true;
            if (item.actor != null) {
                p.actorName = item.actor.name;
                if (item.actor instanceof ConnectApi.ActorWithId) {
                    p.actorId = ((ConnectApi.ActorWithId) item.actor).id;
                }
                if (item.actor instanceof ConnectApi.User) {
                    ConnectApi.Photo photo = ((ConnectApi.User) item.actor).photo;
                    p.actorPhotoUrl = photo == null ? null : photo.smallPhotoUrl;
                }
            }
        }

        ConnectApi.FeedElementCapabilities caps = element.capabilities;
        if (caps == null) {
            return p;
        }

        if (caps.chatterLikes != null) {
            p.isLiked = caps.chatterLikes.isLikedByCurrentUser == true;
            p.likeCount = caps.chatterLikes.page == null ? 0 : caps.chatterLikes.page.total;
        }

        if (caps.comments != null && caps.comments.page != null) {
            p.commentCount = caps.comments.page.total;
            if (caps.comments.page.items != null) {
                for (ConnectApi.Comment c : caps.comments.page.items) {
                    p.comments.add(toComment(c));
                }
            }
        }

        if (caps.interactions != null && caps.interactions.count != null) {
            p.viewCount = Integer.valueOf(caps.interactions.count);
        }

        if (caps.questionAndAnswers != null) {
            p.questionTitle = caps.questionAndAnswers.questionTitle;
        }

        if (caps.poll != null) {
            PollInfo poll = new PollInfo();
            poll.myChoiceId = caps.poll.myChoiceId;
            poll.totalVotes = caps.poll.totalVoteCount == null ? 0 : caps.poll.totalVoteCount;
            for (ConnectApi.FeedPollChoice choice : caps.poll.choices) {
                PollChoice pc = new PollChoice();
                pc.id = choice.id;
                pc.text = choice.text;
                pc.voteCount = choice.voteCount == null ? 0 : choice.voteCount;
                poll.choices.add(pc);
            }
            p.poll = poll;
        }

        if (caps.recordSnapshot != null && caps.recordSnapshot.recordView != null) {
            ConnectApi.RecordView view = caps.recordSnapshot.recordView;
            RecordCard card = new RecordCard();
            card.id = view.id;
            card.name = view.name;
            card.type = view.type;
            p.record = card;
        }

        if (caps.files != null && caps.files.items != null) {
            for (ConnectApi.Content content : caps.files.items) {
                FileInfo f = new FileInfo();
                f.id = content.id;
                f.title = content.title;
                p.files.add(f);
            }
        }

        if (caps.link != null) {
            p.linkUrl = caps.link.url;
            p.linkName = String.isBlank(caps.link.urlName) ? caps.link.url : caps.link.urlName;
        }

        if (caps.trackedChanges != null && caps.trackedChanges.changes != null) {
            for (ConnectApi.TrackedChangeItem change : caps.trackedChanges.changes) {
                p.changes.add(
                    change.fieldName +
                        ' from ' +
                        (String.isBlank(change.oldValue) ? 'blank' : change.oldValue) +
                        ' to ' +
                        (String.isBlank(change.newValue) ? 'blank' : change.newValue) +
                        '.'
                );
            }
        }
        return p;
    }

    private static FeedCommentItem toComment(ConnectApi.Comment c) {
        FeedCommentItem item = new FeedCommentItem();
        item.id = c.id;
        item.text = c.body == null ? '' : c.body.text;
        item.relativeDate = c.relativeCreatedDate;
        if (c.user != null) {
            item.userId = c.user.id;
            item.userName = c.user.displayName;
            item.userPhotoUrl = c.user.photo == null ? null : c.user.photo.smallPhotoUrl;
        }
        return item;
    }

    @TestVisible
    private static List<Segment> toSegments(ConnectApi.AbstractMessageBody body) {
        List<Segment> result = new List<Segment>();
        if (body == null || body.messageSegments == null) {
            return result;
        }
        for (ConnectApi.MessageSegment seg : body.messageSegments) {
            Segment s = new Segment();
            s.type = 'text';
            s.text = seg.text;
            if (seg instanceof ConnectApi.EntityLinkSegment) {
                ConnectApi.EntityLinkSegment link = (ConnectApi.EntityLinkSegment) seg;
                if (link.reference != null) {
                    s.type = 'record';
                    s.recordId = link.reference.id;
                }
            } else if (seg instanceof ConnectApi.MentionSegment) {
                ConnectApi.MentionSegment mention = (ConnectApi.MentionSegment) seg;
                if (mention.record != null) {
                    s.type = 'record';
                    s.recordId = mention.record.id;
                }
            } else if (seg instanceof ConnectApi.LinkSegment) {
                s.type = 'link';
                s.url = ((ConnectApi.LinkSegment) seg).url;
            } else if (seg instanceof ConnectApi.MarkupEndSegment) {
                ConnectApi.MarkupType tag = ((ConnectApi.MarkupEndSegment) seg).markupType;
                if (tag != ConnectApi.MarkupType.Paragraph && tag != ConnectApi.MarkupType.ListItem) {
                    continue;
                }
                s.text = '\n';
            } else if (seg instanceof ConnectApi.MarkupBeginSegment) {
                continue;
            }
            if (String.isEmpty(s.text)) {
                continue;
            }
            result.add(s);
        }
        return result;
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}