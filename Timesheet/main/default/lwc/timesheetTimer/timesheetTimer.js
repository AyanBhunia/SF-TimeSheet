import { LightningElement, wire, api } from 'lwc';
import getTimerInitData from '@salesforce/apex/TimesheetTimerController.getTimerInitData';
import startTimer from '@salesforce/apex/TimesheetTimerController.startTimer';
import pauseTimer from '@salesforce/apex/TimesheetTimerController.pauseTimer';
import continueTimer from '@salesforce/apex/TimesheetTimerController.continueTimer';
import saveTimer from '@salesforce/apex/TimesheetTimerController.saveTimer';
import discardTimer from '@salesforce/apex/TimesheetTimerController.discardTimer';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import TIMESHEET_LINE_ITEM_OBJECT from '@salesforce/schema/Timesheet_Line_Item__c';
import ACTIVITY_FIELD from '@salesforce/schema/Timesheet_Line_Item__c.Activity__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { EnclosingUtilityId, updateUtility } from 'lightning/platformUtilityBarApi';
import FORM_FACTOR from '@salesforce/client/formFactor';
import desktopTemplate from './timesheetTimer.html';
import phoneTemplate from './phone.html';

// Keeps timers in other open tabs, and the weekly grid, in step with this one.
const SYNC_CHANNEL = 'timesheet-timer-sync';
const MS_PER_HOUR = 60 * 60 * 1000;
const IDLE_LABEL = 'Timer';
const LABEL_PROJECT_CHARS = 20;
// Picks up hour edits made elsewhere (record page, another device) while a timer exists.
const REFRESH_MS = 5 * 60 * 1000;

export default class TimesheetTimer extends LightningElement {
    @api label;
    // Set on pages shared with desktop (Employee Overview) so the timer only shows on phones.
    @api phoneOnly = false;
    isPhone = FORM_FACTOR === 'Small';
    isLoading = true;
    formattedTime = '00:00:00';

    selectedProject = '';
    selectedActivity = '';
    projectOptions = [];
    activityOptions = [];
    description = '';

    // The running timer as returned by Apex (null when idle).
    timer;
    clockOffsetMs = 0;
    timerInterval;
    utilityLabel;
    utilityHighlighted;

    // Set only when this component sits in a utility bar.
    @wire(EnclosingUtilityId)
    wiredUtilityId(utilityId) {
        this.utilityId = utilityId;
        this.updateUtilityBar();
    }

    render() {
        return this.isPhone ? phoneTemplate : desktopTemplate;
    }

    get isHidden() {
        return this.phoneOnly && !this.isPhone;
    }

    get today() {
        return new Date();
    }

    @wire(getObjectInfo, { objectApiName: TIMESHEET_LINE_ITEM_OBJECT })
    objectInfo;

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: ACTIVITY_FIELD })
    wiredActivityPicklistValues({ data }) {
        if (data) {
            this.activityOptions = data.values.map(item => ({ label: item.label, value: item.value }));
        }
    }

    connectedCallback() {
        if (this.isHidden) return;
        // Timers started on another device only show up after a reload, so reload when
        // the app or tab comes back to the foreground (e.g. the phone is unlocked).
        this.visibilityHandler = () => {
            if (document.visibilityState === 'visible' && !this.isLoading) {
                this.loadInitData();
            }
        };
        document.addEventListener('visibilitychange', this.visibilityHandler);
        if (typeof BroadcastChannel !== 'undefined') {
            this.syncChannel = new BroadcastChannel(SYNC_CHANNEL);
            this.syncChannel.onmessage = () => this.loadInitData();
        }
        this.refreshInterval = setInterval(() => {
            if (this.timer && !this.isLoading) {
                this.loadInitData();
            }
        }, REFRESH_MS);
        this.loadInitData();
    }

    disconnectedCallback() {
        this.stopClock();
        clearInterval(this.refreshInterval);
        if (this.visibilityHandler) {
            document.removeEventListener('visibilitychange', this.visibilityHandler);
        }
        if (this.syncChannel) {
            this.syncChannel.close();
        }
    }

    loadInitData() {
        this.isLoading = true;
        return getTimerInitData()
            .then(result => {
                this.projectOptions = result.projects || [];
                this.applyTimer(result.activeTimer);
            })
            .catch(error => this.showError(error, 'Failed to load the timer'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Show the server's timer state (or the idle screen when null).
    applyTimer(timer) {
        this.stopClock();
        const sameTimer = !!timer && !!this.timer && this.timer.id === timer.id;
        this.timer = timer || null;
        if (this.timer) {
            this.clockOffsetMs = this.timer.serverNowMs - Date.now();
            // A background reload must not wipe a description being typed.
            if (!sameTimer || !this.descriptionEdited) {
                this.description = this.timer.description || '';
                this.descriptionEdited = false;
            }
            if (this.isRunning) {
                this.timerInterval = setInterval(() => this.updateTimeDisplay(), 1000);
            }
        } else {
            this.selectedProject = '';
            this.selectedActivity = '';
            this.description = '';
            this.descriptionEdited = false;
        }
        this.updateTimeDisplay();
    }

    // Runs an Apex action, then refreshes this tab and the other tabs.
    // affectsHours: the action changed Duration__c or removed a line item (save, discard).
    runAction(action, params, successMessage, affectsHours = false) {
        // Ignore a second click (double tap) while a request is in flight.
        if (this.isLoading) return Promise.resolve();
        this.isLoading = true;
        return action(params)
            .then(result => {
                this.applyTimer(result);
                if (successMessage) {
                    this.showToast('Success', successMessage, 'success');
                }
                if (this.syncChannel) {
                    this.syncChannel.postMessage({ changed: true, affectsHours });
                }
            })
            .catch(error => {
                this.showError(error, 'Timer action failed');
                // The server state may differ from the screen (timer stopped or started
                // elsewhere, row deleted), so show what the server has now.
                return this.loadInitData();
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get isRunning() {
        return !!this.timer && !this.timer.pauseStartMs;
    }

    get isPendingSave() {
        return !!this.timer && !!this.timer.pauseStartMs;
    }

    get showPicklists() {
        return !this.timer;
    }

    get showTaskInfo() {
        return !!this.timer;
    }

    get activeProjectName() {
        return this.timer ? this.timer.projectName : '';
    }

    get activeActivityName() {
        return this.timer ? this.timer.activity : '';
    }

    get startDisabled() {
        return this.isLoading || !this.selectedProject || !this.selectedActivity;
    }

    get inputsDisabled() {
        return this.isLoading;
    }

    get hasNoProjects() {
        return !this.isLoading && !this.timer && this.projectOptions.length === 0;
    }

    get phoneTimeClass() {
        return 'phone-time' + (this.isRunning ? ' running' : this.isPendingSave ? ' paused' : '');
    }

    get atDailyMax() {
        return !!this.timer && this.totalMs() >= this.timer.capHours * MS_PER_HOUR;
    }

    get statusText() {
        if (this.isRunning) return 'Running';
        if (this.atDailyMax) return 'Daily maximum reached. Save or Discard.';
        if (this.isPendingSave && !this.isStartDay) return 'Started on an earlier day. Save or Discard.';
        if (this.isPendingSave && this.timer.autoStopped) {
            return 'Stopped at the ' + this.timer.workdayHours + 'h workday limit. Continue or Save.';
        }
        if (this.isPendingSave) return 'Paused - save or continue';
        return 'Ready';
    }

    // The clock includes hours already on the line item; say so.
    get baseText() {
        const base = this.timer ? Number(this.timer.baseHours) || 0 : 0;
        return base > 0 ? 'includes ' + base.toFixed(2) + 'h already logged' : '';
    }

    get timerClass() {
        return 'time-display slds-text-align_center slds-m-vertical_large' + (this.isRunning ? ' running' : '');
    }

    // A paused timer can only be continued on the day it started.
    get continueDisabled() {
        return this.isLoading || this.atDailyMax || !this.isStartDay;
    }

    // Compare with the server's date: the browser may be in another time zone.
    get isStartDay() {
        return !this.timer || !this.timer.timerDate || this.timer.timerDate === this.timer.serverToday;
    }

    get saveDisabled() {
        return this.isLoading || this.elapsedMs() / MS_PER_HOUR <= 0.1;
    }

    handleProjectChange(event) {
        this.selectedProject = event.detail.value;
    }

    handleActivityChange(event) {
        this.selectedActivity = event.detail.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
        this.descriptionEdited = true;
    }

    handleStart() {
        this.runAction(startTimer, { projectId: this.selectedProject, activity: this.selectedActivity });
    }

    handlePause() {
        this.runAction(pauseTimer, { lineItemId: this.timer.id });
    }

    handleContinue() {
        this.runAction(continueTimer, { lineItemId: this.timer.id });
    }

    handleSave() {
        this.runAction(saveTimer, { lineItemId: this.timer.id, description: this.description }, 'Time logged successfully!', true);
    }

    handleDiscard() {
        this.runAction(discardTimer, { lineItemId: this.timer.id }, 'Timer discarded', true);
    }

    // Line item total shown on the clock: saved hours plus this timer's time.
    totalMs() {
        if (!this.timer) return 0;
        return (Number(this.timer.baseHours) || 0) * MS_PER_HOUR + this.elapsedMs();
    }

    // Worked time of this timer session in milliseconds.
    elapsedMs() {
        if (!this.timer) return 0;
        const end = this.timer.pauseStartMs || Date.now() + this.clockOffsetMs;
        return Math.max(0, end - this.timer.startMs - (this.timer.pausedMs || 0));
    }

    stopClock() {
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
            this.timerInterval = null;
        }
    }

    updateTimeDisplay() {
        // At the limit the server stops the timer; reload so every tab and device agrees.
        // The clock stops first, so a failed reload does not retry every second; at most
        // every few seconds, in case this clock is slightly ahead of the server's.
        const limitMs = (this.timer ? this.timer.limitHours - (Number(this.timer.limitBase) || 0) : 0) * MS_PER_HOUR;
        if (this.isRunning && this.elapsedMs() >= limitMs
            && !this.isLoading && Date.now() - (this.limitReloadAt || 0) > 3000) {
            this.limitReloadAt = Date.now();
            this.stopClock();
            this.loadInitData();
        }
        const totalSeconds = Math.floor(this.totalMs() / 1000);
        const hours = Math.floor(totalSeconds / 3600);
        const minutes = Math.floor((totalSeconds % 3600) / 60);
        const seconds = totalSeconds % 60;
        this.formattedTime = [hours, minutes, seconds].map(v => String(v).padStart(2, '0')).join(':');
        this.updateUtilityBar();
    }

    // Shows the clock on the utility bar button, so the timer is visible while the panel is closed.
    updateUtilityBar() {
        if (!this.utilityId) return;
        let label = IDLE_LABEL;
        if (this.timer) {
            const name = this.timer.projectName || '';
            const shortName = name.length > LABEL_PROJECT_CHARS ? name.slice(0, LABEL_PROJECT_CHARS - 1) + '…' : name;
            label = (this.isRunning ? '' : 'Paused ') + this.formattedTime + (shortName ? ' · ' + shortName : '');
        }
        const highlighted = !!this.timer;
        if (label !== this.utilityLabel || highlighted !== this.utilityHighlighted) {
            this.utilityLabel = label;
            this.utilityHighlighted = highlighted;
            // One call for both: separate calls left the bar label unchanged in testing.
            this.callUtilityApi(() => updateUtility(this.utilityId, { label, highlighted }));
        }
    }

    // The bar label is cosmetic; never let it break the timer.
    callUtilityApi(call) {
        try {
            Promise.resolve(call()).catch(() => {});
        } catch (e) {
            // ignore
        }
    }

    showError(error, fallback) {
        this.showToast('Error', (error && error.body && error.body.message) || fallback, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
