import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getFeed from '@salesforce/apex/ChatterFeedController.getFeed';
import postText from '@salesforce/apex/ChatterFeedController.postText';
import postPoll from '@salesforce/apex/ChatterFeedController.postPoll';
import postQuestion from '@salesforce/apex/ChatterFeedController.postQuestion';
import setLike from '@salesforce/apex/ChatterFeedController.setLike';
import postComment from '@salesforce/apex/ChatterFeedController.postComment';
import votePoll from '@salesforce/apex/ChatterFeedController.votePoll';
import deletePost from '@salesforce/apex/ChatterFeedController.deletePost';

const SORT_OPTIONS = [
    { label: 'Latest Posts', value: 'CreatedDateDesc' },
    { label: 'Most Recent Activity', value: 'LastModifiedDateDesc' }
];
const MAX_POLL_CHOICES = 10;

const RECORD_ICONS = {
    Task: 'standard:task',
    Event: 'standard:event',
    Account: 'standard:account',
    Contact: 'standard:contact',
    Lead: 'standard:lead',
    Opportunity: 'standard:opportunity',
    Case: 'standard:case',
    EmailMessage: 'standard:email'
};

let choiceKey = 0;
const newChoice = () => ({ key: `choice-${choiceKey++}`, value: '' });

export default class CustomChatterFeed extends NavigationMixin(LightningElement) {
    @api recordId;

    items = [];
    nextPageToken;
    currentUserPhotoUrl;
    isLoading = false;
    isLoadingMore = false;
    error;

    sortOrder = 'CreatedDateDesc';
    searchTerm = '';
    appliedSearch = '';

    publisherTab = 'post'; 
    publisherExpanded = false;
    postBody = '';
    pollQuestion = '';
    pollChoices = [newChoice(), newChoice()];
    questionTitle = '';
    questionDetails = '';
    isPosting = false;

    openMenu = null;
    commentDrafts = {};
    activeCommentId = null;

    connectedCallback() {
        this.handleDocumentClick = this.handleDocumentClick.bind(this);
        document.addEventListener('click', this.handleDocumentClick);
        if (this.recordId) {
            this.loadFeed();
        }
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.handleDocumentClick);
    }

    renderedCallback() {
        this.template.querySelectorAll('textarea[data-field]').forEach((el) => {
            const value = this[el.dataset.field] || '';
            if (el.value !== value) {
                el.value = value;
            }
        });
    }

    handleDocumentClick(event) {
        if (!this.openMenu) {
            return;
        }
        const path = event.composedPath();
        const zones = [...this.template.querySelectorAll('.menu-zone')];
        if (!zones.some((zone) => path.includes(zone))) {
            this.openMenu = null;
        }
    }


    async loadFeed() {
        this.isLoading = true;
        try {
            const page = await getFeed({
                recordId: this.recordId,
                sortOrder: this.sortOrder,
                searchTerm: this.appliedSearch,
                pageToken: null
            });
            this.items = page.items || [];
            this.nextPageToken = page.nextPageToken;
            this.currentUserPhotoUrl = page.currentUserPhotoUrl;
            this.error = undefined;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleLoadMore() {
        this.isLoadingMore = true;
        try {
            const page = await getFeed({
                recordId: this.recordId,
                sortOrder: this.sortOrder,
                searchTerm: this.appliedSearch,
                pageToken: this.nextPageToken
            });
            this.items = [...this.items, ...(page.items || [])];
            this.nextPageToken = page.nextPageToken;
        } catch (e) {
            this.toast('Error', reduceError(e), 'error');
        } finally {
            this.isLoadingMore = false;
        }
    }

    get feedItems() {
        return this.items.map((item) => this.decorate(item));
    }

    get hasItems() {
        return this.items.length > 0;
    }

    get showEmpty() {
        return !this.hasItems && !this.isLoading && !this.error;
    }

    get emptyMessage() {
        return this.appliedSearch
            ? `No posts match "${this.appliedSearch}".`
            : 'No posts yet. Share an update to get the conversation started.';
    }

    decorate(item) {
        const withKeys = (segments, prefix) =>
            (segments || []).map((s, i) => ({
                ...s,
                key: `${item.id}-${prefix}${i}`,
                isRecord: s.type === 'record',
                isLink: s.type === 'link',
                isText: s.type !== 'record' && s.type !== 'link'
            }));

        const body = withKeys(item.body, 'b');
        const poll = item.poll ? this.decoratePoll(item) : null;
        const record = item.record
            ? { ...item.record, iconName: RECORD_ICONS[item.record.type] || 'standard:record' }
            : null;

        return { ...item, headerSegments: withKeys(item.header, 'h'), bodySegments: body, hasBody: body.some((s) => s.text && s.text.trim()), 
            poll, record, hasFiles: item.files && item.files.length > 0, hasChanges: item.changes && item.changes.length > 0, 
            changeItems: (item.changes || []).map((text, i) => ({ key: `${item.id}-c${i}`, text })), viewLabel: item.viewCount > 0 ? `${item.viewCount} ${item.viewCount === 1 ? 'view' : 'views'}` : '', 
            likeSummary: item.likeCount > 0 ? `${item.likeCount} ${item.likeCount === 1 ? 'like' : 'likes'}` : '', likeLabel: item.isLiked ? 'Liked' : 'Like', likeClass: `feed-action${item.isLiked ? ' feed-action_active' : ''}`,
             hasComments: item.comments && item.comments.length > 0, showAllCommentsLink: item.commentCount > (item.comments || []).length, allCommentsLabel: `View all ${item.commentCount} comments`, menuOpen: this.openMenu === item.id, 
             commentDraft: this.commentDrafts[item.id] || '', hasCommentDraft: !!(this.commentDrafts[item.id] || '').trim(), commentActive: this.activeCommentId === item.id};
    }

    decoratePoll(item) {
        const { poll } = item;
        const hasVoted = !!poll.myChoiceId;
        return {
            ...poll,
            hasVoted,
            voteSummary: `${poll.totalVotes} ${poll.totalVotes === 1 ? 'vote' : 'votes'}`,
            choices: poll.choices.map((c) => {
                const percent = poll.totalVotes ? Math.round((c.voteCount / poll.totalVotes) * 100) : 0;
                const isMine = c.id === poll.myChoiceId;
                return {
                    ...c,
                    isMine,
                    percentLabel: `${percent}%`,
                    barStyle: `width: ${percent}%`,
                    choiceClass: `poll-choice${isMine ? ' poll-choice_mine' : ''}`
                };
            })
        };
    }

    get isPostTab() {
        return this.publisherTab === 'post';
    }

    get isPollTab() {
        return this.publisherTab === 'poll';
    }

    get isQuestionTab() {
        return this.publisherTab === 'question';
    }

    get postTabClass() {
        return this.pubTabClass('post');
    }

    get pollTabClass() {
        return this.pubTabClass('poll');
    }

    get questionTabClass() {
        return this.pubTabClass('question');
    }

    pubTabClass(tab) {
        return `pub-tab${this.publisherTab === tab ? ' pub-tab_active' : ''}`;
    }

    get pollChoiceRows() {
        return this.pollChoices.map((c, i) => ({ ...c, label: `Choice ${i + 1}`, index: i }));
    }

    get canAddChoice() {
        return this.pollChoices.length < MAX_POLL_CHOICES;
    }

    get shareLabel() {
        return this.isPostTab ? 'Share' : 'Ask';
    }

    selectPublisherTab(event) {
        this.publisherTab = event.currentTarget.dataset.tab;
        this.publisherExpanded = this.publisherTab !== 'post' || !!this.postBody;
    }

    expandPublisher() {
        this.publisherExpanded = true;
        requestAnimationFrame(() => {
            const input = this.template.querySelector('.pub-textarea');
            if (input) {
                input.focus();
            }
        });
    }

    handlePublisherInput(event) {
        this[event.target.dataset.field] = event.target.value;
    }

    handleChoiceInput(event) {
        const index = Number(event.target.dataset.index);
        this.pollChoices = this.pollChoices.map((c, i) => (i === index ? { ...c, value: event.target.value } : c));
    }

    addChoice() {
        if (this.canAddChoice) {
            this.pollChoices = [...this.pollChoices, newChoice()];
        }
    }

    resetPublisher() {
        this.postBody = '';
        this.pollQuestion = '';
        this.pollChoices = [newChoice(), newChoice()];
        this.questionTitle = '';
        this.questionDetails = '';
        this.publisherExpanded = false;
    }

    async handleShare() {
        if (this.isPostTab && !this.publisherExpanded) {
            this.expandPublisher();
            return;
        }
        this.isPosting = true;
        try {
            if (this.isPostTab) {
                await postText({ recordId: this.recordId, text: this.postBody });
            } else if (this.isPollTab) {
                await postPoll({
                    recordId: this.recordId,
                    question: this.pollQuestion,
                    choices: this.pollChoices.map((c) => c.value)
                });
            } else {
                await postQuestion({
                    recordId: this.recordId,
                    title: this.questionTitle,
                    details: this.questionDetails
                });
            }
            this.resetPublisher();
            this.publisherTab = 'post';
            await this.loadFeed();
        } catch (e) {
            this.toast('Error', reduceError(e), 'error');
        } finally {
            this.isPosting = false;
        }
    }

    get sortMenuOpen() {
        return this.openMenu === 'sort';
    }

    get sortOptions() {
        return SORT_OPTIONS.map((o) => ({ ...o, selected: o.value === this.sortOrder }));
    }

    get hasSearchTerm() {
        return !!this.searchTerm;
    }

    toggleSortMenu() {
        this.openMenu = this.sortMenuOpen ? null : 'sort';
    }

    handleSortPick(event) {
        event.preventDefault();
        this.openMenu = null;
        const value = event.currentTarget.dataset.value;
        if (value !== this.sortOrder) {
            this.sortOrder = value;
            this.loadFeed();
        }
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
    }

    handleSearchKeyup(event) {
        if (event.key === 'Enter') {
            this.appliedSearch = this.searchTerm.trim();
            this.loadFeed();
        }
    }

    clearSearch() {
        this.searchTerm = '';
        if (this.appliedSearch) {
            this.appliedSearch = '';
            this.loadFeed();
        }
    }

    handleRefresh() {
        this.loadFeed();
    }


    toggleItemMenu(event) {
        const id = event.currentTarget.dataset.id;
        this.openMenu = this.openMenu === id ? null : id;
    }

    async handleDelete(event) {
        event.preventDefault();
        const id = event.currentTarget.dataset.id;
        this.openMenu = null;
        const confirmed = await LightningConfirm.open({
            message: 'Are you sure you want to delete this post?',
            label: 'Delete Post',
            theme: 'warning'
        });
        if (!confirmed) {
            return;
        }
        try {
            await deletePost({ feedElementId: id });
            this.items = this.items.filter((item) => item.id !== id);
            this.toast('Success', 'Post was deleted.', 'success');
        } catch (e) {
            this.toast('Error', reduceError(e), 'error');
        }
    }

    async handleLike(event) {
        const id = event.currentTarget.dataset.id;
        const item = this.items.find((i) => i.id === id);
        const liked = !item.isLiked;
        this.items = this.items.map((i) =>
            i.id === id ? { ...i, isLiked: liked, likeCount: i.likeCount + (liked ? 1 : -1) } : i
        );
        try {
            await setLike({ feedElementId: id, liked });
        } catch (e) {
            this.toast('Error', reduceError(e), 'error');
            this.loadFeed();
        }
    }

    handleCommentClick(event) {
        const id = event.currentTarget.dataset.id;
        this.activeCommentId = id;
        requestAnimationFrame(() => {
            const input = this.template.querySelector(`.comment-input[data-id="${id}"]`);
            if (input) {
                input.focus();
            }
        });
    }

    handleCommentFocus(event) {
        this.activeCommentId = event.target.dataset.id;
    }

    handleCommentInput(event) {
        this.commentDrafts = { ...this.commentDrafts, [event.target.dataset.id]: event.target.value };
    }

    handleCommentKeydown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.submitComment(event.target.dataset.id);
        }
    }

    handleCommentSubmit(event) {
        this.submitComment(event.currentTarget.dataset.id);
    }

    async submitComment(id) {
        const text = (this.commentDrafts[id] || '').trim();
        if (!text) {
            return;
        }
        try {
            await postComment({ feedElementId: id, text });
            this.commentDrafts = { ...this.commentDrafts, [id]: '' };
            this.activeCommentId = null;
            await this.loadFeed();
        } catch (e) {
            this.toast('Error', reduceError(e), 'error');
        }
    }

    async handleVote(event) {
        const { id, choice } = event.currentTarget.dataset;
        try {
            await votePoll({ feedElementId: id, choiceId: choice });
            await this.loadFeed();
        } catch (e) {
            this.toast('Error', reduceError(e), 'error');
        }
    }

    navigateToRecord(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.recordId, actionName: 'view' }
        });
    }

    openFile(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: event.currentTarget.dataset.recordId }
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

function reduceError(error) {
    if (!error) return 'Unknown error';
    if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(', ');
    if (error.body && error.body.message) return error.body.message;
    return error.message || 'Unknown error';
}