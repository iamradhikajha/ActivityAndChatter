import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class ActivityTimelineItem extends NavigationMixin(LightningElement) {
    @api item;

    menuOpen = false;

    connectedCallback() {
        this.handleDocumentClick = this.handleDocumentClick.bind(this);
        document.addEventListener('click', this.handleDocumentClick);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.handleDocumentClick);
    }

    get lineClass() {
        return `tl-line ${this.item.isEmail ? 'tl-line_email' : 'tl-line_task'}`;
    }

    get ariaExpanded() {
        return String(!!this.item.expanded);
    }

    handleDocumentClick(event) {
        if (!this.menuOpen) {
            return;
        }
        const zone = this.template.querySelector('.menu-zone');
        if (!zone || !event.composedPath().includes(zone)) {
            this.menuOpen = false;
        }
    }

    toggleMenu() {
        this.menuOpen = !this.menuOpen;
    }

    handleMenuPick(event) {
        event.preventDefault();
        const action = event.currentTarget.dataset.value;
        this.menuOpen = false;
        if (action === 'view') {
            this.navigate(this.item.id);
            return;
        }
        this.dispatchEvent(new CustomEvent('itemaction', { detail: { id: this.item.id, action } }));
    }

    handleToggle() {
        this.dispatchEvent(new CustomEvent('toggle', { detail: { id: this.item.id } }));
    }

    handleComplete(event) {
        this.dispatchEvent(
            new CustomEvent('complete', { detail: { id: this.item.id, completed: event.target.checked } })
        );
    }

    handleNavigate(event) {
        event.preventDefault();
        this.navigate(event.currentTarget.dataset.id);
    }

    navigate(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }
}