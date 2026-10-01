public with sharing class ActivityApexConstants {
    public static final Integer DEFAULT_PAST_LIMIT = 10;
    public static final Integer MAX_LIMIT = 500;
    public static final Integer SUBJECT_MAX_LENGTH = 255;
    public static final Integer DESCRIPTION_MAX_LENGTH = 32000;
    public static final String TYPE_TASK = 'Task';
    public static final String TYPE_EMAIL = 'Email';
    public static final String SUBTYPE_TASK = 'Task';
    public static final String SUBTYPE_EMAIL = 'Email';
    public static final String SUBTYPE_LIST_EMAIL = 'ListEmail';
    public static final List<String> EMAIL_SUBTYPES = new List<String>{ SUBTYPE_EMAIL, SUBTYPE_LIST_EMAIL };
    public static final List<String> ALL_SUBTYPES = new List<String>{
        SUBTYPE_TASK,
        SUBTYPE_EMAIL,
        SUBTYPE_LIST_EMAIL
    };

    public static final String FILTER_ALL = 'all';
    public static final String FILTER_MINE = 'mine';
    public static final String RANGE_LAST_7 = 'last7';
    public static final String RANGE_NEXT_7 = 'next7';
    public static final String RANGE_LAST_30 = 'last30';
    public static final Integer DAYS_7 = 7;
    public static final Integer DAYS_30 = 30;
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_NOT_STARTED = 'Not Started';
    public static final String EMAIL_SUBJECT_PREFIX = 'Email: ';
    public static final String NO_SUBJECT = '(No subject)';
    public static final String TO_LABEL = 'To: ';
    public static final String CC_LABEL = 'CC: ';
    public static final String ADDRESS_SEPARATOR = ', ';
    public static final String ADDRESS_SPLIT_REGEX = '[,;\\s]+';
    public static final String HTML_BREAK_REGEX = '<br\\s*/?>';
    public static final String NEW_LINE = '\n';
    public static final String ERR_RECORD_ID_REQUIRED = 'A record Id is required.';
    public static final String ERR_RECIPIENT_REQUIRED = 'Enter at least one recipient.';
    public static final String ERR_EMAIL_NOT_SENT = 'Email could not be sent: ';
}