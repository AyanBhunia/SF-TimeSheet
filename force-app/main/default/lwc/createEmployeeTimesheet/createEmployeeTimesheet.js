import getEmployee from '@salesforce/apex/GetEmployeeDetails.getEmployee';
import getTimesheetsLineItems from '@salesforce/apex/GetRangeOfTimesheetsLineItems.getTimesheetsLineItems';
import imageLogo from '@salesforce/resourceUrl/dbtLogo';
import JS_PDF from '@salesforce/resourceUrl/jsPDF';
import jsPDFAutoTable from '@salesforce/resourceUrl/jsPdfAutotable';
import { loadScript } from 'lightning/platformResourceLoader';
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CreateEmployeeTimesheet extends LightningElement {
    @api recordId;
    @track isGeneratingPDF = false;

    // Private properties
    Employee;
    TimesheetLineItems = [];
    sd;
    ed;
    startDate = "No Start Date";
    endDate = "No End Date";
    Client = "";
    totalDurationAttendance = 0;
    totalDurationAbsence = 0;

    // Constants
    weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    // PDF Generation states
    jsPDFInitialized = false;
    loadError = false;
    isLoading = true;

    /**
     * @description Clears existing toasts and shows new toast
     */
    showToast(title, message, variant) {
        this.dispatchEvent(new CustomEvent('lightning__showtoast', {
            bubbles: true,
            composed: true,
            detail: { mode: 'clear' }
        }));

        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    /**
     * @description Lifecycle hook to initialize PDF libraries
     */
    renderedCallback() {
        if (this.jsPDFInitialized) return;
        this.initializePDFLibraries();
    }

    /**
     * @description Initializes PDF libraries
     */
    async initializePDFLibraries() {
        this.jsPDFInitialized = true;
        try {
            await Promise.all([
                loadScript(this, JS_PDF),
                loadScript(this, jsPDFAutoTable)
            ]);
            this.isLoading = false;
        } catch (error) {
            console.error('Error loading PDF libraries:', error);
            this.loadError = true;
            this.isLoading = false;
            this.showToast('Error', 'Failed to load PDF libraries', 'error');
        }
    }

    /**
     * @description Handles click event for generating timesheet
     */
    async handleClick() {
        if (!this.validateDates()) return;

        try {
            this.isGeneratingPDF = true;

            // Parallel data fetching
            const [employeeData, timesheetData] = await Promise.all([
                this.fetchEmployeeData(),
                this.fetchTimesheetData()
            ]);

            if (!timesheetData?.length) {
                this.showToast('Warning', 'No Timesheet Items found for the selected period.', 'warning');
                return;
            }

            this.Employee = employeeData;
            this.TimesheetLineItems = timesheetData;
            this.processTimesheetData();
            console.time('pdf');
            await this.handleGeneratePDF();
            console.timeEnd('pdf');
            
        } catch (error) {
            console.error('Error processing timesheet:', error);
            if (error.message !== 'No timesheet items found') {
                this.showToast('Error', 'Error generating timesheet', 'error');
            }
        } finally {
            this.isGeneratingPDF = false;
        }
    }

    /**
     * @description Validates date inputs
     */
    validateDates() {
        const startDate = this.template.querySelector('.start-date');
        const endDate = this.template.querySelector('.end-date');

        if (!startDate.value || !endDate.value) {
            this.showToast('Warning', 'Please enter start and end date', 'warning');
            return false;
        }

        this.sd = new Date(startDate.value);
        this.ed = new Date(endDate.value);

        if (this.ed < this.sd) {
            this.showToast('Warning', 'End date must be after start date', 'warning');
            return false;
        }

        return true;
    }

    /**
     * @description Fetches employee data
     */
    async fetchEmployeeData() {
        try {
            const employee = await getEmployee({ recID: this.recordId });
            this.Client = employee.dbt__Project_Employees__r
                ?.map(el => el.dbt__Project_Name__c)
                .join(', ') || '';
            return employee;
        } catch (error) {
            console.error('Error fetching employee:', error);
            throw error;
        }
    }

    /**
     * @description Fetches timesheet data
     */
    async fetchTimesheetData() {
        try {
            return await getTimesheetsLineItems({
                recID: this.recordId,
                startDate: this.sd,
                endDate: this.ed
            });
        } catch (error) {
            console.error('Error fetching timesheets:', error);
            throw error;
        }
    }
	
    /**
     * @description Processes timesheet data
     */
    processTimesheetData() {
        const dateSet = new Set(this.TimesheetLineItems.map(item => item.dbt__Date__c));
        
        this.resetTotals();
        this.processExistingTimeSheets();
        this.addMissingDates(dateSet);
        this.sortTimesheetItems();
        this.addTotalRow();
        this.setDateRange();
    }

    /**
     * @description Resets totals
     */
    resetTotals() {
        this.totalDurationAttendance = 0;
        this.totalDurationAbsence = 0;
    }

    /**
     * @description Process existing timesheet entries
     */
    processExistingTimeSheets() {
        this.TimesheetLineItems = this.TimesheetLineItems.map(element => {
            const date = new Date(element.dbt__Date__c);
            const processedElement = {
                ...element,
                duration: element.duration.toString(),
                Day: this.weekdays[date.getDay()]
            };

            if (element.dbt__Type__c === "Attendance") {
                this.totalDurationAttendance += parseFloat(element.duration || 0);
            } else if (element.dbt__Type__c === "Absence") {
                this.totalDurationAbsence += parseFloat(element.duration || 0);
            }

            return processedElement;
        });
    }

    /**
     * @description Sets date range
     */
    setDateRange() {
        this.startDate = this.sd.toISOString().split("T")[0];
        this.endDate = this.ed.toISOString().split("T")[0];
    }

    /**
     * @description Adds missing dates
     */
    addMissingDates(dateSet) {
        const currentDate = new Date(this.sd);
        const endDate = new Date(this.ed);
        const missingDates = [];

        while (currentDate <= endDate) {
            const formattedDate = currentDate.toISOString().split("T")[0];
            
            if (!dateSet.has(formattedDate)) {
                missingDates.push({
                    dbt__Date__c: formattedDate,
                    duration: "0",
                    Day: this.weekdays[currentDate.getDay()],
                    dbt__Type__c: "Missing"
                });
            }
            
            currentDate.setDate(currentDate.getDate() + 1);
        }

        this.TimesheetLineItems = [...this.TimesheetLineItems, ...missingDates];
    }

    /**
     * @description Sorts timesheet items
     */
    sortTimesheetItems() {
        this.TimesheetLineItems.sort((a, b) => {
            const dateA = new Date(a.dbt__Date__c);
            const dateB = new Date(b.dbt__Date__c);
            const dateDiff = dateA - dateB;
            
            return dateDiff || (b.dbt__Type__c > a.dbt__Type__c ? 1 : -1);
        });
    }

    /**
     * @description Adds total row
     */
    addTotalRow() {
        this.TimesheetLineItems.push({
            Day: " ",
            dbt__Date__c: "Total",
            dbt__Type__c: "Attendance",
            duration: this.totalDurationAttendance.toString()
        });
    }

    /**
     * @description Generates PDF
     */
    async handleGeneratePDF() {
        if (!this.validatePDFGeneration()) return;

        try {
            const doc = new window.jspdf.jsPDF({
                orientation: 'portrait',
                unit: 'mm',
                format: 'a4'
                // , compress: true  // Not Compressing faster execution, but increases file size.
            });

            this.addPDFContent(doc);
            doc.save(`timesheet_${this.startDate}_${this.endDate}.pdf`);
            this.showToast('Success', 'PDF generated successfully', 'success');
        } catch (error) {
            console.error('Error generating PDF:', error);
            this.showToast('Error', 'Failed to generate PDF', 'error');
            throw error;
        }
    }

    /**
     * @description Validates PDF generation
     */
    validatePDFGeneration() {
        if (this.loadError) {
            this.showToast('Error', 'PDF libraries failed to load', 'error');
            return false;
        }
        if (this.isLoading) {
            this.showToast('Warning', 'Please wait, libraries are loading', 'warning');
            return false;
        }
        if (!this.jsPDFInitialized) {
            this.showToast('Error', 'PDF library not initialized', 'error');
            return false;
        }
        return true;
    }

    /**
     * @description Adds content to PDF
     */
    addPDFContent(doc) {
        this.addHeader(doc);
        this.addTable(doc);
    }

    /**
     * @description Adds header to PDF
     */
    addHeader(doc) {
        const contractorName = this.Employee?.Name || "Unknown Contractor";
        const clientmanagerName = this.Employee?.Client_Manager__r?.Name || "Unknown Manager";
        const clientmanagerEmail = this.Employee?.Client_Manager_email__c || "No Email Provided";

        const pic = new Image();
        pic.src = imageLogo;

        doc.text("Name of Contractor: " + contractorName, 10, 10);
        doc.addImage(pic, 190, 2, 15, 15);
        doc.text("Client: " + this.Client, 10, 20);
        doc.text("Name of Manager: " + clientmanagerName, 10, 30);
        doc.text("Period Ending: " + this.endDate, 10, 40);
        doc.text("Please email Completed & Signed to: " + clientmanagerEmail, 10, 50);
    }

    /**
     * @description Adds table to PDF
     */
    addTable(doc) {
        const footer = [this.TimesheetLineItems.pop()];
        const columns = [
            { header: "Day", dataKey: "Day" },
            { header: "Date", dataKey: "dbt__Date__c" },
            { header: "Hours Worked", dataKey: "duration" }
        ];
        const rows = this.TimesheetLineItems.map(row => ({
            Day: row.Day,
            dbt__Date__c: row.dbt__Date__c,
            duration: row.duration,
        }));

        doc.autoTable({
            theme: 'grid',
            columns: columns,
            body: rows,
            foot: footer,
            startY: 60,
            alternateRowStyles: { fillColor: [245, 245, 245] },
            headStyles: {
                fillColor: [0, 172, 148],
                textColor: [255, 255, 255],
                fontSize: 13,
                fontStyle: 'bold',
                cellPadding: 2.5,
                valign: 'middle',
                halign: 'center'
            },
            bodyStyles: {
                fontSize: 11,
                cellPadding: 1.5,
                valign: 'middle',
                halign: 'center'
            },
            footStyles: {
                fillColor: [128, 157, 60],
                textColor: [255, 255, 255],
                fontStyle: 'bold',
                fontSize: 12,
                cellPadding: 2.5,
                valign: 'middle',
                halign: 'center'
            },
            didParseCell: this.handleCellStyling
        });
    }

    /**
     * @description Handles cell styling
     */
    handleCellStyling(data) {
        const { row, cell, column } = data;
        const day = row.raw?.Day;
        const duration = row.raw?.duration;

        if (column.dataKey === 'duration' && duration === '0') {
            cell.styles.fillColor = [255, 179, 142];
        }

        if (day === 'Saturday' || day === 'Sunday') {
            cell.styles.fillColor = [179, 200, 207];
        }
    }

    get generateButtonLabel() {
        return this.isGeneratingPDF ? 'Generating PDF...' : 'Generate PDF';
    }

    get isButtonDisabled() {
        return this.isGeneratingPDF || this.isLoading;
    }
}