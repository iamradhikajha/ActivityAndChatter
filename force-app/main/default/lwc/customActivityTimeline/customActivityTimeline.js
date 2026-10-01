import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { deleteRecord } from 'lightning/uiRecordApi';
import LightningConfirm from 'lightning/confirm';
import LOCALE from '@salesforce/i18n/locale';
import getActivities from '@salesforce/apex/ActivityTimelineController.getActivities';
import getRecordContext from '@salesforce/apex/ActivityTimelineController.getRecordContext';
import setTaskCompleted from '@salesforce/apex/ActivityTimelineController.setTaskCompleted';
import logEmail from '@salesforce/apex/ActivityTimelineController.logEmail';

const DATE_OPTIONS = [
    { label: 'All time', value: 'all' },
    { label: 'Last 7 days', value: 'last7' },
    { label: 'Next 7 days', value: 'next7' },
    { label: 'Last 30 days', value: 'last30' }
];
const OWNER_OPTIONS = [
    { label: 'All activities', value: 'all' },
    { label: 'My activities', value: 'mine' }
];
const TYPE_OPTIONS = [
    { label: 'All types', value: 'all' },
    { label: 'Tasks', value: 'Task' },
    { label: 'Emails', value: 'Email' }
];
const DEFAULT_FILTERS = { dateRange: 'all', owner: 'all', type: 'all' };
const UPCOMING_KEY = 'upcoming';
const EMPTY_EMAIL = { to: '', cc: '', subject: '', body: '', date: null };

export default class CustomActivityTimeline extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    upcoming = [];
    past = [];
    hasMorePast = false;
    viewAll = false;
    isLoading = false;
    error;

    context = {};
    filters = { ...DEFAULT_FILTERS };
    draftFilters = { ...DEFAULT_FILTERS };
    showFilterPanel = false;

    expanded = {};
    collapsedSections = {};

    showTaskModal = false;
    taskMode = 'new';
    editRecordId;
    isSavingTask = false;

    showEmailModal = false;
    emailMode = 'log';
    emailDraft = { ...EMPTY_EMAIL };
    isSendingEmail = false;

    dateOptions = DATE_OPTIONS;
    ownerOptions = OWNER_OPTIONS;
    typeOptions = TYPE_OPTIONS;

    openMenu = null;

    connectedCallback() {
        this.handleDocumentClick = this.handleDocumentClick.bind(this);
        document.addEventListener('click', this.handleDocumentClick);
        this.refreshHandlerId = registerRefreshHandler(this, this.refreshHandler.bind(this));
        if (!this.recordId) {
            return;
        }
        this.loadContext();
        this.loadActivities();
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.handleDocumentClick);
        unregisterRefreshHandler(this.refreshHandlerId);
    }

    refreshHandler() {
        return this.loadActivities().then(() => true);
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

    get isTaskMenuOpen() {
        return this.openMenu === 'task';
    }

    get isEmailMenuOpen() {
        return this.openMenu === 'email';
    }

    get taskArrowClass() {
        return `action-arrow${this.isTaskMenuOpen ? ' is-active' : ''}`;
    }

    get emailArrowClass() {
        return `action-arrow${this.isEmailMenuOpen ? ' is-active' : ''}`;
    }

    toggleMenu(event) {
        const menu = event.currentTarget.dataset.menu;
        this.openMenu = this.openMenu === menu ? null : menu;
    }

    handleMenuPick(event) {
        event.preventDefault();
        const { menu, value } = event.currentTarget.dataset;
        this.openMenu = null;
        if (menu === 'task') {
            this.openTaskModal(value);
        } else if (value === 'send') {
            this.openStandardEmail();
        } else {
            this.openEmailModal();
        }
    }

    async loadContext() {
        try {
            this.context = await getRecordContext({ recordId: this.recordId });
        } catch (e) {
            this.context = {};
        }
    }

    async loadActivities() {
        this.isLoading = true;
        try {
            const data = await getActivities({
                recordId: this.recordId,
                dateRange: this.filters.dateRange,
                ownerFilter: this.filters.owner,
                typeFilter: this.filters.type,
                viewAll: this.viewAll
            });
            this.upcoming = data.upcoming || [];
            this.past = data.past || [];
            this.hasMorePast = data.hasMorePast;
            this.error = undefined;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    get upcomingItems() {
        return this.upcoming.map((item) => this.decorate(item));
    }

    get hasUpcoming() {
        return this.upcoming.length > 0;
    }

    get upcomingSection() {
        return this.sectionState(UPCOMING_KEY);
    }

    get pastGroups() {
        const sorted = [...this.past].sort((a, b) => (a.effectiveDate < b.effectiveDate ? 1 : -1));
        const groups = new Map();
        sorted.forEach((item) => {
            const date = parseDate(item.effectiveDate);
            const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
            if (!groups.has(key)) {
                groups.set(key, { key, label: monthLabel(date), items: [] });
            }
            groups.get(key).items.push(this.decorate(item));
        });
        return [...groups.values()].map((group) => ({ ...group, ...this.sectionState(group.key) }));
    }

    get hasPast() {
        return this.past.length > 0;
    }

    get filterSummary() {
        return [
            optionLabel(DATE_OPTIONS, this.filters.dateRange),
            optionLabel(OWNER_OPTIONS, this.filters.owner),
            optionLabel(TYPE_OPTIONS, this.filters.type)
        ].join(' • ');
    }

    get allIds() {
        return [...this.upcoming, ...this.past].map((item) => item.id);
    }

    get isAllExpanded() {
        const ids = this.allIds;
        return ids.length > 0 && ids.every((id) => this.expanded[id]);
    }

    get expandAllLabel() {
        return this.isAllExpanded ? 'Collapse All' : 'Expand All';
    }

    sectionState(key) {
        const isOpen = !this.collapsedSections[key];
        return {
            key,
            isOpen,
            ariaExpanded: String(isOpen),
            sectionClass: `slds-section${isOpen ? ' slds-is-open' : ''}`,
            chevron: isOpen ? 'utility:chevrondown' : 'utility:chevronright'
        };
    }

    decorate(item) {
        const isEmail = item.type === 'Email';
        const expanded = !!this.expanded[item.id];
        const actor = item.isMine ? 'You' : item.ownerName || 'Someone';
        const have = item.isMine ? 'have' : 'has';

        let summaryPrefix;
        let whoConnector = ' with ';
        if (isEmail) {
            summaryPrefix = item.isClosed ? `${actor} sent an email` : `${actor} ${have} an upcoming email`;
            whoConnector = ' to ';
        } else if (item.isClosed) {
            summaryPrefix = `${actor} had a task`;
        } else {
            summaryPrefix = `${actor} ${have} ${item.isOverdue ? 'an overdue' : 'an upcoming'} task`;
        }

        const dateSource = item.isClosed ? item.effectiveDate : item.activityDate;
        return {...item,isEmail, isTask: !isEmail, expanded, iconName: isEmail ? 'standard:email' : 'standard:task', 
            iconLabel: isEmail ? 'Email' : 'Task', expandIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright', 
            expandLabel: `${expanded ? 'Collapse' : 'Expand'} ${item.subject}`, dateLabel: dateSource ? formatDate(parseDate(dateSource)) : '', 
            dateClass: `tl-date${item.isOverdue ? ' tl-date_overdue' : ''}`, summaryPrefix, whoConnector, showWhat: !!item.whatId && item.whatId !== this.recordId, 
            whatConnector: ' about ', dueDateLabel: item.activityDate ? formatLongDate(parseDate(item.activityDate)) : '—', hasDescription: !!item.description};
    }

    handleRefresh(event) {
        event.preventDefault();
        this.loadActivities();
    }

    handleExpandAll(event) {
        event.preventDefault();
        if (this.isAllExpanded) {
            this.expanded = {};
        } else {
            const expanded = {};
            this.allIds.forEach((id) => {
                expanded[id] = true;
            });
            this.expanded = expanded;
            this.collapsedSections = {};
        }
    }

    handleViewAll(event) {
        event.preventDefault();
        this.viewAll = true;
        this.loadActivities();
    }

    handleShowAllActivities() {
        this.filters = { ...DEFAULT_FILTERS };
        this.draftFilters = { ...DEFAULT_FILTERS };
        this.viewAll = true;
        this.loadActivities();
    }


    toggleFilterPanel() {
        this.draftFilters = { ...this.filters };
        this.showFilterPanel = !this.showFilterPanel;
    }

    handleFilterChange(event) {
        this.draftFilters = { ...this.draftFilters, [event.target.dataset.filter]: event.detail.value };
    }

    handleRestoreDefaults() {
        this.draftFilters = { ...DEFAULT_FILTERS };
    }

    handleApplyFilters() {
        this.filters = { ...this.draftFilters };
        this.showFilterPanel = false;
        this.loadActivities();
    }

    toggleSection(event) {
        const key = event.currentTarget.dataset.key;
        this.collapsedSections = { ...this.collapsedSections, [key]: !this.collapsedSections[key] };
    }

    toggleItem(event) {
        const { id } = event.detail;
        this.expanded = { ...this.expanded, [id]: !this.expanded[id] };
    }

    async handleToggleComplete(event) {
        const { id, completed } = event.detail;
        try {
            await setTaskCompleted({ taskId: id, completed });
            this.toast('Success', completed ? 'Task marked complete.' : 'Task reopened.', 'success');
        } catch (e) {
            this.toast('Error', reduceError(e), 'error');
        }
        this.loadActivities();
    }

    async handleItemAction(event) {
        const { id, action } = event.detail;
        if (action === 'edit') {
            this.openTaskModal('edit', id);
        } else if (action === 'delete') {
            const confirmed = await LightningConfirm.open({
                message: 'Are you sure you want to delete this activity?',
                label: 'Delete Activity',
                theme: 'warning'
            });
            if (!confirmed) {
                return;
            }
            try {
                await deleteRecord(id);
                this.toast('Success', 'Activity was deleted.', 'success');
                this.loadActivities();
            } catch (e) {
                this.toast('Error', reduceError(e), 'error');
            }
        }
    }

    handleNewTask() {
        this.openTaskModal('new');
    }

    openTaskModal(mode, recordId) {
        this.taskMode = mode;
        this.editRecordId = recordId;
        this.taskView = 'expanded';
        this.showTaskModal = true;
    }

    closeTaskModal() {
        this.showTaskModal = false;
        this.editRecordId = undefined;
        this.isSavingTask = false;
    }

    taskView = 'expanded';
    taskRestoreView = 'expanded';

    get taskComposerClass() {
        return `composer composer_${this.taskView}`;
    }

    get showTaskBackdrop() {
        return this.taskView === 'expanded';
    }

    get isTaskMinimized() {
        return this.taskView === 'minimized';
    }

    get taskMinimizeTitle() {
        return this.isTaskMinimized ? 'Restore' : 'Minimize';
    }

    get taskDockIcon() {
        return this.taskView === 'expanded' ? 'utility:contract_alt' : 'utility:expand_alt';
    }

    get taskDockTitle() {
        return this.taskView === 'expanded' ? 'Dock' : 'Expand';
    }

    toggleMinimizeTask() {
        if (this.isTaskMinimized) {
            this.taskView = this.taskRestoreView;
        } else {
            this.taskRestoreView = this.taskView;
            this.taskView = 'minimized';
        }
    }

    toggleDockTask() {
        this.taskView = this.taskView === 'expanded' ? 'docked' : 'expanded';
    }

    handleComposerHeaderClick() {
        if (this.isTaskMinimized) {
            this.taskView = this.taskRestoreView;
        }
    }

    get isEditMode() {
        return this.taskMode === 'edit';
    }

    get taskModalTitle() {
        if (this.taskMode === 'edit') {
            return 'Edit Activity';
        }
        return this.taskMode === 'log' ? 'Log a Completed Task' : 'New Task';
    }

    get defaultWhoId() {
        return this.context.isWhoRecord ? this.recordId : undefined;
    }

    get defaultWhatId() {
        return this.context.isWhoRecord ? undefined : this.recordId;
    }

    get canRelateWhat() {
        return this.context.canRelateWhat !== false;
    }

    get defaultTaskStatus() {
        return this.taskMode === 'log' ? this.context.closedStatus : this.context.openStatus;
    }

    get defaultTaskDate() {
        return this.taskMode === 'log' ? toIsoDate(new Date()) : undefined;
    }

    handleTaskSubmit() {
        this.isSavingTask = true;
    }

    handleTaskSuccess() {
        const message = this.isEditMode ? 'Activity was saved.' : 'Task was created.';
        this.closeTaskModal();
        this.toast('Success', message, 'success');
        this.loadActivities();
    }

    handleTaskError() {
        this.isSavingTask = false;
    }

    handleNewEmail() {
        this.openStandardEmail();
    }

    openStandardEmail() {
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: { apiName: 'Global.SendEmail' },
            state: { recordId: this.recordId }
        });
    }
    openEmailModal() {
        this.emailDraft = {
            ...EMPTY_EMAIL,
            to: this.context.defaultEmail || '',
            date: toIsoDate(new Date())
        };
        this.showEmailModal = true;
    }

    closeEmailModal() {
        this.showEmailModal = false;
        this.isSendingEmail = false;
    }

    get isLogEmail() {
        return this.emailMode === 'log';
    }

    get emailModalTitle() {
        return this.isLogEmail ? 'Log an Email' : 'Send Email';
    }

    get emailSubmitLabel() {
        return this.isLogEmail ? 'Save' : 'Send';
    }

    handleEmailFieldChange(event) {
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.emailDraft = { ...this.emailDraft, [event.target.dataset.field]: value };
    }

    async handleEmailSubmit() {
        const inputs = [...this.template.querySelectorAll('.email-input')];
        const valid = inputs.reduce((ok, input) => input.reportValidity() && ok, true);
        if (!valid) {
            return;
        }
        this.isSendingEmail = true;
        const { to, subject, body, date } = this.emailDraft;
        try {
            await logEmail({ recordId: this.recordId, toAddresses: to, subject, htmlBody: body, emailDate: date });
            this.toast('Success', 'Email was logged.', 'success');
            this.closeEmailModal();
            this.loadActivities();
        } catch (e) {
            this.isSendingEmail = false;
            this.toast('Error', reduceError(e), 'error');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

function optionLabel(options, value) {
    const match = options.find((o) => o.value === value);
    return match ? match.label : value;
}

function parseDate(value) {
    const [y, m, d] = String(value).substring(0, 10).split('-').map(Number);
    return new Date(y, m - 1, d);
}

function toIsoDate(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2,'0' )}`;
}

function dayDiff(date) {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    return Math.round((date - today) / 86400000);
}

function formatDate(date) {
    const diff = dayDiff(date);
    if (diff === 0) return 'Today';
    if (diff === 1) return 'Tomorrow';
    if (diff === -1) return 'Yesterday';
    const opts = { month: 'short', day: 'numeric' };
    if (date.getFullYear() !== new Date().getFullYear()) {
        opts.year = 'numeric';
    }
    return new Intl.DateTimeFormat(LOCALE, opts).format(date);
}

function formatLongDate(date) {
    return new Intl.DateTimeFormat(LOCALE, { month: 'short', day: 'numeric', year: 'numeric' }).format(date);
}

function monthLabel(date) {
    const now = new Date();
    const monthsAgo = (now.getFullYear() - date.getFullYear()) * 12 + (now.getMonth() - date.getMonth());
    if (monthsAgo === 0) return 'This Month';
    if (monthsAgo === 1) return 'Last Month';
    return `${new Intl.DateTimeFormat(LOCALE, { month: 'long' }).format(date)} • ${date.getFullYear()}`;
}

function reduceError(error) {
    if (!error) return 'Unknown error';
    if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(', ');
    if (error.body && error.body.message) return error.body.message;
    return error.message || 'Unknown error';
}