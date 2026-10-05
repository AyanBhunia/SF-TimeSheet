import { LightningElement } from 'lwc';
import getContext from '@salesforce/apex/PtoController.getContext';

const SECTIONS = [
    { name: 'overview', label: 'Overview' },
    { name: 'apply', label: 'Apply' },
    { name: 'past', label: 'Past' },
    { name: 'approve', label: 'Approve', approverOnly: true }
];

const NO_EMPLOYEE =
    "Your user isn't linked to an employee record. Ask HR to set User on your Employee record.";

export default class PtoApp extends LightningElement {
    context;
    error;
    isLoading = true;
    active = 'overview';

    connectedCallback() {
        this.load();
    }

    async load() {
        this.isLoading = true;
        try {
            this.context = await getContext();
            this.error = undefined;
            if (this.active === 'approve' && !this.context.canApprove) {
                this.active = 'overview';
            }
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'The PTO tab could not load.';
        } finally {
            this.isLoading = false;
        }
    }

    get tabs() {
        const canApprove = this.context?.canApprove;
        const pending = this.context?.pendingCount || 0;
        return SECTIONS.filter((s) => !s.approverOnly || canApprove).map((s) => {
            const isActive = s.name === this.active;
            return {
                name: s.name,
                label: s.name === 'approve' && pending > 0 ? `${s.label} (${pending})` : s.label,
                liClass: 'slds-tabs_default__item' + (isActive ? ' slds-is-active' : ''),
                ariaSelected: isActive ? 'true' : 'false',
                tabIndex: isActive ? '0' : '-1'
            };
        });
    }

    get subtitle() {
        const employee = this.context?.employee;
        if (!employee) {
            return this.context?.isHrAdmin ? 'HR Admin' : '';
        }
        const parts = [employee.name];
        if (employee.available !== null && employee.available !== undefined) {
            parts.push(`${formatHours(employee.available)} h available`);
        }
        parts.push(employee.hasManager ? `Manager: ${employee.managerName}` : 'No manager set');
        return parts.join(' · ');
    }

    get hasEmployee() {
        return !!this.context?.employee;
    }

    get isHrAdmin() {
        return !!this.context?.isHrAdmin;
    }

    get employeeId() {
        return this.context?.employee?.id;
    }

    get noEmployeeMessage() {
        return NO_EMPLOYEE;
    }

    get canApplyForSomeone() {
        return this.hasEmployee || (this.context?.employees || []).length > 0;
    }

    get isOverview() {
        return this.active === 'overview';
    }

    get isApply() {
        return this.active === 'apply';
    }

    get isPast() {
        return this.active === 'past';
    }

    get isApprove() {
        return this.active === 'approve';
    }

    handleTab(event) {
        event.preventDefault();
        this.active = event.currentTarget.dataset.name;
    }

    handleChanged() {
        this.load();
    }
}

function formatHours(value) {
    const n = Number(value) || 0;
    return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/0$/, '');
}
