import { LightningElement, api,track } from 'lwc';

export default class CustomActivityChatter extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api defaultTab = 'Activity';

    activeTab = 'activity';
    chatterLoaded = false;



    selectTab(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        if (this.activeTab === 'chatter') {
            this.chatterLoaded = true;
        }
    }

    get activitySelected() {
        return String(this.activeTab === 'activity');
    }

    get chatterSelected() {
        return String(this.activeTab === 'chatter');
    }
    
    get activityTabClass() {
        return `tab${this.activeTab === 'activity' ? ' tab_active' : ''}`;
    }

    get chatterTabClass() {
        return `tab${this.activeTab === 'chatter' ? ' tab_active' : ''}`;
    }

    get activityPanelClass() {
        return `panel${this.activeTab === 'activity' ? '' : ' panel_hidden'}`;
    }

    get chatterPanelClass() {
        return `panel${this.activeTab === 'chatter' ? '' : ' panel_hidden'}`;
    }
}