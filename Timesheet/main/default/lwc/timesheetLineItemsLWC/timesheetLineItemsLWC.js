import { LightningElement, track, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import updateTimesheetLineItems from "@salesforce/apex/TimesheetLineItemLwcController.updateTimesheetLineItems";
import getProjects from "@salesforce/apex/ProjectController.getProjects";
import getTimesheetLineItems from "@salesforce/apex/TimesheetLineItemLwcController.getTimesheetLineItems";

import START_DATE from "@salesforce/schema/Timesheet__c.Start_Date__c";
import END_DATE from "@salesforce/schema/Timesheet__c.End_Date__c";
import EMPLOYEE_NAME from "@salesforce/schema/Timesheet__c.Employee__r.Name";
import EMPLOYEE_ID from "@salesforce/schema/Timesheet__c.Employee__r.Id";

const fields = [START_DATE, END_DATE, EMPLOYEE_NAME, EMPLOYEE_ID];

export default class TimesheetLineItemsLWC extends LightningElement {
  @track timeSheetLineItems = [];
  wiredLineItems;
  error;
  itemsToDelete = [];
  optionArray = [];
  empId;
  empName;
  projectId;
  @api recordId;

  @wire(getTimesheetLineItems, { timesheetId: "$recordId" })
  wiredTimesheetLineItems(result) {
    this.wiredLineItems = result;
    if (result.data) {
      this.handleData(result.data);
    } else if (result.error) {
      this.error = result.error;
    }
  }

  @wire(getRecord, { recordId: "$recordId", fields })
  timesheet;

  get startDate() {
    return getFieldValue(this.timesheet.data, START_DATE);
  }

  get endDate() {
    return getFieldValue(this.timesheet.data, END_DATE);
  }

  get employeeName() {
    return getFieldValue(this.timesheet.data, EMPLOYEE_NAME);
  }

  get employeeId() {
    return getFieldValue(this.timesheet.data, EMPLOYEE_ID);
  }

  get options() {
    return this.optionArray;
  }

  populateProjects() {
    this.getProjectValues(this.employeeId);
  }

  getProjectValues(empIDFromMethod) {
    getProjects({ empId: empIDFromMethod }).then((result) => {
      let arr = [];
      for (let i = 0; i < result.length; i++) {
        arr.push({
          label: result[i].dbt__Project__r.Name,
          value: result[i].dbt__Project__c
        });
      }
      this.optionArray = arr;
    });
  }

  createEmptyRow(items) {
    let timesheetLineItem = {};
    if (items.length > 0) {
      timesheetLineItem.index = items[items.length - 1].index + 1;
    } else {
      timesheetLineItem.index = 1;
    }
    timesheetLineItem.dbt__Type__c = "Attendance";
    timesheetLineItem.dbt__Timesheet__c = this.recordId;
    timesheetLineItem.dbt__Date__c = new Date().toISOString().split("T")[0];
    timesheetLineItem.dbt__Project__c = null;
    timesheetLineItem.dbt__Activity__c = null;
    timesheetLineItem.dbt__Absence_Category__c = null;
    timesheetLineItem.dbt__Duration__c = null;
    timesheetLineItem.dbt__Description__c = null;
    timesheetLineItem.isAttendance = true;
    timesheetLineItem.isAbsence = false;
    this.timeSheetLineItems.push(timesheetLineItem);
  }

  addNewRow() {
    this.createEmptyRow(this.timeSheetLineItems);
  }

  update() {
    updateTimesheetLineItems({
      timesheetLineItems: this.timeSheetLineItems,
      idsToDelete: this.itemsToDelete
    })
      .then(() => {
        let event = new ShowToastEvent({
          title: "Success",
          message: "Successfully Updated",
          variant: "success",
          mode: "dismissible"
        });
        this.dispatchEvent(event);
        return refreshApex(this.wiredLineItems);
      })
      .catch((error) => {
        let errorMessages = [];
        let fieldErrors = error.body.fieldErrors;
        let pageErrors = error.body.pageErrors;
        let errors = Object.values(fieldErrors);
        errors.forEach((error) => errorMessages.push(error[0].message));
        pageErrors.forEach((error) => errorMessages.push(error.message));
        errorMessages.forEach((errorMessage) =>
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Error",
              message: errorMessage,
              variant: "error",
              mode: "dismissible"
            })
          )
        );
      });
    this.itemsToDelete = [];
  }

  handleChange(event) {
    let index = event.target.dataset.id;
    let field = event.target.name;
    let value = event.target.value;
    for (let i = 0; i < this.timeSheetLineItems.length; i++) {
      if (this.timeSheetLineItems[i].index === parseInt(index)) {
        this.timeSheetLineItems[i][field] = value;
      }
    }
    for (let i = 0; i < this.timeSheetLineItems.length; i++) {
      if (this.timeSheetLineItems[i].dbt__Type__c === "Absence") {
        this.timeSheetLineItems[i].isAbsence = true;
        this.timeSheetLineItems[i].isAttendance = false;
        this.timeSheetLineItems[i].dbt__Project__c = null;
        this.timeSheetLineItems[i].dbt__Activity__c = null;
      } else if (this.timeSheetLineItems[i].dbt__Type__c === "Attendance") {
        this.timeSheetLineItems[i].isAbsence = false;
        this.timeSheetLineItems[i].isAttendance = true;
        this.timeSheetLineItems[i].dbt__Absence_Category__c = null;
      }
      if (this.timeSheetLineItems[i].dbt__Type__c === "Absence") {
        if (this.timeSheetLineItems[i].dbt__Absence_Category__c === "Holiday") {
          this.timeSheetLineItems[i].dbt__Duration__c = 8;
        }
      }
    }
  }

  handleCancel() {
    location.reload();
  }

  handleData(data) {
    if (data.length <= 0) {
      this.createEmptyRow(this.timeSheetLineItems);
    } else if (data.length > 0) {
      let items = [];
      for (let i = 0; i < data.length; i++) {
        let timesheetLineItem = {};
        timesheetLineItem.index = i + 1;
        timesheetLineItem.Id = data[i].Id;
        timesheetLineItem.dbt__Type__c = data[i].dbt__Type__c;
        timesheetLineItem.dbt__Timesheet__c = data[i].dbt__Timesheet__c;
        timesheetLineItem.dbt__Date__c = data[i].dbt__Date__c;
        timesheetLineItem.dbt__Project__c = data[i].dbt__Project__c;
        timesheetLineItem.dbt__Activity__c = data[i].dbt__Activity__c;
        timesheetLineItem.dbt__Absence_Category__c = data[i].dbt__Absence_Category__c;
        timesheetLineItem.dbt__Duration__c = data[i].dbt__Duration__c;
        timesheetLineItem.dbt__Description__c = data[i].dbt__Description__c;
        if (timesheetLineItem.dbt__Type__c === "Attendance") {
          timesheetLineItem.isAttendance = true;
          timesheetLineItem.isAbsence = false;
        } else if (timesheetLineItem.dbt__Type__c === "Absence") {
          timesheetLineItem.isAttendance = false;
          timesheetLineItem.isAbsence = true;
        }
        items.push(timesheetLineItem);
      }
      this.timeSheetLineItems = items;
      this.error = undefined;
    }
    this.populateProjects();
  }

  deleteItem(event) {
    let toBeDeletedRowIndex = event.target.dataset.id;
    let timeSheetLineItems = [];
    for (let i = 0; i < this.timeSheetLineItems.length; i++) {
      let tempRecord = Object.assign({}, this.timeSheetLineItems[i]); //cloning object
      if (tempRecord.index != toBeDeletedRowIndex) {
        timeSheetLineItems.push(tempRecord);
      } else {
        this.itemsToDelete.push(tempRecord.Id);
      }
    }
    for (let i = 0; i < timeSheetLineItems.length; i++) {
      timeSheetLineItems[i].index = i + 1;
    }
    this.timeSheetLineItems = timeSheetLineItems;
  }
}