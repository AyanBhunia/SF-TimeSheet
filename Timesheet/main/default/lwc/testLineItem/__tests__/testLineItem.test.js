import { createElement } from 'lwc';
import TestLineItem from 'c/testLineItem';
import getWeeklyTimesheetItems from '@salesforce/apex/WeeklyTimesheetController.getWeeklyTimesheetItems';
import getTimesheet from '@salesforce/apex/WeeklyTimesheetController.getTimesheet';
import saveWeek from '@salesforce/apex/WeeklyTimesheetController.saveWeek';

jest.mock('@salesforce/apex/WeeklyTimesheetController.getWeeklyTimesheetItems', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/WeeklyTimesheetController.getTimesheet', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/WeeklyTimesheetController.getProjects', () => ({
    default: jest.fn(() => Promise.resolve([
        { dbt__Project__c: 'p1', dbt__Project__r: { Name: 'Dev Timer', dbt__Billable__c: 'Yes' }, dbt__Hourly_Rate__c: 10 }
    ]))
}), { virtual: true });
jest.mock('@salesforce/apex/WeeklyTimesheetController.getProjectActivities', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/WeeklyTimesheetController.getEmployeeTimesheetItems', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/WeeklyTimesheetController.saveWeek', () => ({ default: jest.fn(() => Promise.resolve({ success: true })) }), { virtual: true });

const flush = async () => {
    for (let i = 0; i < 10; i++) {
        await new Promise(resolve => setTimeout(resolve, 0));
    }
};

const item = (id, date, duration, activity = 'Analysis') => ({
    Id: id,
    dbt__Type__c: 'Attendance',
    dbt__Date__c: date,
    dbt__Project__c: 'p1',
    dbt__Activity__c: activity,
    dbt__Duration__c: duration,
    dbt__Description__c: 'Timer is updating',
    dbt__Project__r: { dbt__Billable__c: 'Yes' }
});

async function renderGrid(startDate, endDate, itemsBySheet) {
    getTimesheet.mockResolvedValue({ dbt__Employee__c: 'emp1', dbt__Start_Date__c: startDate, dbt__End_Date__c: endDate, name: 'TS' });
    getWeeklyTimesheetItems.mockImplementation(({ timesheetId }) => Promise.resolve(itemsBySheet[timesheetId] || []));
    const element = createElement('c-test-line-item', { is: TestLineItem });
    element.recordId = 'ts1';
    document.body.appendChild(element);
    await flush();
    return element;
}

const projectInputs = element => element.shadowRoot.querySelectorAll('lightning-input[data-for="project"]');
const headers = element => [...element.shadowRoot.querySelectorAll('thead th')].map(th => th.textContent.replace(/\s+/g, ' ').trim());
const button = (element, label) => [...element.shadowRoot.querySelectorAll('lightning-button')].find(b => b.label === label);

async function clickSave(element) {
    button(element, 'Save').dispatchEvent(new CustomEvent('click'));
    await flush();
}

async function editHours(element, dayIndex, value) {
    const input = [...projectInputs(element)].find(i => i.dataset.dayIndex === String(dayIndex));
    input.value = value;
    input.dispatchEvent(new CustomEvent('change'));
    await flush();
}

describe('c-test-line-item on a timesheet that does not start on Monday', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows a Friday item in the Friday column and an unedited Save sends nothing', async () => {
        const element = await renderGrid('2026-10-23', '2026-10-29', { ts1: [item('a1', '2026-10-23', 0.22)] });

        expect(headers(element)[1]).toContain('Friday');
        expect(headers(element)[1]).toContain('23');
        expect(projectInputs(element)[0].value).toBe(0.22);

        await clickSave(element);
        await clickSave(element);

        // Before the fix the row was sent with Date__c 2026-10-27 and moved to another day on every Save.
        expect(saveWeek).not.toHaveBeenCalled();
    });

    it('saves an edited Friday item with its own date', async () => {
        const element = await renderGrid('2026-10-23', '2026-10-29', { ts1: [item('a1', '2026-10-23', 0.22)] });

        await editHours(element, 0, 1.5);
        await clickSave(element);

        expect(saveWeek).toHaveBeenCalledTimes(1);
        const { upserts, deletes } = saveWeek.mock.calls[0][0];
        expect(upserts).toHaveLength(1);
        expect(upserts[0].Id).toBe('a1');
        expect(upserts[0].dbt__Date__c).toBe('2026-10-23');
        expect(upserts[0].dbt__Duration__c).toBe(1.5);
        expect(deletes).toHaveLength(0);
    });

    it('updates the Total Hours row of the edited column', async () => {
        const element = await renderGrid('2026-10-23', '2026-10-29', { ts1: [item('a1', '2026-10-23', 0.22)] });
        const totalHours = () => {
            const row = [...element.shadowRoot.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('Total Hours'));
            return [...row.querySelectorAll('td')].slice(1, 8).map(td => td.textContent.trim());
        };

        expect(totalHours()).toEqual(['0.22', '0', '0', '0', '0', '0', '0']);
        await editHours(element, 4, 2);
        expect(totalHours()).toEqual(['0.22', '0', '0', '0', '2', '0', '0']);
    });

    it('keeps two activities of one project on their own days', async () => {
        const element = await renderGrid('2026-10-23', '2026-10-29', {
            ts1: [item('a1', '2026-10-23', 0.22, 'Analysis'), item('a2', '2026-10-27', 0.25, 'Testing')]
        });

        const rows = element.shadowRoot.querySelectorAll('tbody tr.slds-hint-parent');
        expect(rows).toHaveLength(2);
        await clickSave(element);
        expect(saveWeek).not.toHaveBeenCalled();
    });

    it('leaves an item outside the grid days alone on Save', async () => {
        const element = await renderGrid('2026-10-23', '2026-10-29', {
            ts1: [item('a1', '2026-10-23', 0.22), item('out', '2026-10-30', 2, 'Testing')]
        });

        await editHours(element, 0, 1);
        await clickSave(element);

        const { upserts, deletes } = saveWeek.mock.calls[0][0];
        expect(upserts.map(u => u.Id)).toEqual(['a1']);
        expect(deletes).toHaveLength(0);
    });

    it('copies a Monday item from a Monday-start week into the Monday column', async () => {
        const element = await renderGrid('2026-10-23', '2026-10-29', {
            ts1: [],
            prev: [item('old', '2026-10-19', 3)]
        });

        const combobox = element.shadowRoot.querySelector('lightning-combobox[data-id="prevTimesheet"]');
        combobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'prev' } }));
        button(element, 'Copy').dispatchEvent(new CustomEvent('click'));
        await flush();
        await clickSave(element);

        const { upserts } = saveWeek.mock.calls[0][0];
        expect(upserts).toHaveLength(1);
        expect(upserts[0].Id).toBeNull();
        expect(upserts[0].dbt__Date__c).toBe('2026-10-26');
    });
});

describe('c-test-line-item on a Monday-start timesheet', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('keeps Monday to Sunday columns and an unedited Save sends nothing', async () => {
        const element = await renderGrid('2026-10-19', '2026-10-25', { ts1: [item('a1', '2026-10-23', 0.22)] });

        expect(headers(element).slice(1, 8).map(h => h.match(/^[A-Za-z]+/)[0]))
            .toEqual(['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']);
        expect(projectInputs(element)[4].value).toBe(0.22);

        await clickSave(element);
        expect(saveWeek).not.toHaveBeenCalled();
    });
});
