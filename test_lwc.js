const rawList = [{"timesheetStatus":"Submitted","timesheetPeriod":"7/13/2026 to 7/19/2026","timesheetName":"Test 14","timesheetId":"a07Ec00002c9BDIIA2","startDate":"2026-07-13","projectTotalDuration":4.0,"projectName":"Dev","projectLineItemCount":1,"projectId":"a05Ec00000fCQSEIA4","lineItems":[{"attributes":{"type":"dbt__Timesheet_Line_Item__c","url":"/services/data/v67.0/sobjects/dbt__Timesheet_Line_Item__c/a06Ec00000e5um8IAA"},"dbt__Timesheet__c":"a07Ec00002c9BDIIA2","Id":"a06Ec00000e5um8IAA","dbt__Date__c":"2026-07-15","dbt__Duration__c":4.00,"dbt__Project__c":"a05Ec00000fCQSEIA4","dbt__Type__c":"Attendance","dbt__Billable__c":"Yes","dbt__Line_Item_Status__c":"Submitted","dbt__Rejection_Notes__c":"r","dbt__Activity__c":"Mentoring / Training","dbt__Project__r":{"attributes":{"type":"dbt__Project__c","url":"/services/data/v67.0/sobjects/dbt__Project__c/a05Ec00000fCQSEIA4"},"Id":"a05Ec00000fCQSEIA4","Name":"Dev"}}],"isPartialAllowed":true,"id":"a07Ec00002c9BDIIA2_Dev","employeeTotalDuration":4.0,"employeeProjectTotalDuration":4.0,"employeeProjectLineItemCount":1,"employeeName":"Test 1","employeeLineItemCount":1,"employeeId":"a01Ec00002hMCU4IAO","duration":4.00}];

const rows = [];
rawList.forEach((wrapper, wIdx) => {
    const empName = wrapper.employeeName || 'Unknown Employee';
    const tsStatus = wrapper.timesheetStatus || 'Submitted';
    const fallbackDate = wrapper.startDate ? String(wrapper.startDate) : '';
    const tsId = wrapper.timesheetId || wrapper.id;
    const tsName = wrapper.timesheetName || '';
    const isPartialAllowed = wrapper.isPartialAllowed === true;

    if (isPartialAllowed && wrapper.lineItems && wrapper.lineItems.length > 0) {
        wrapper.lineItems.forEach((li, lIdx) => {
            const typeVal = li.dbt__Type__c;
            const isAbsence = typeVal === 'Absence';
            const absenceCat = li.dbt__Absence_Category__c || 'Absence';
            const projObj = li.dbt__Project__r;
            const projId = li.dbt__Project__c;

            const pName = isAbsence
                ? absenceCat
                : (projObj ? projObj.Name : (projId || wrapper.projectName || 'N/A'));

            const aName = isAbsence
                ? '-'
                : (li.dbt__Activity__c || li.dbt__Description__c || typeVal || '-');

            const durVal = li.dbt__Duration__c;
            const dur = durVal !== undefined && durVal !== null ? parseFloat(durVal) : 0;
            const lineItemStatus = li.dbt__Line_Item_Status__c || '';
            const lineDate = li.dbt__Date__c || fallbackDate;

            rows.push({
                id: li.Id || (tsId + '_li_' + lIdx),
                lineItemId: li.Id || null,
                timesheetId: tsId,
                timesheetName: tsName,
                timesheetStatus: tsStatus,
                isPartialAllowed: true,
                employeeId: wrapper.employeeId || null,
                employeeName: empName,
                date: lineDate,
                projectId: projId || null,
                projectName: pName,
                activityName: aName,
                duration: dur,
                status: lineItemStatus,
                lineItemStatus: lineItemStatus,
                statusClass: lineItemStatus
            });
        });
    }
});
console.log(JSON.stringify(rows, null, 2));
