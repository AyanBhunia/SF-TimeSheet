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
    totalDuration = 0;
    totalDays = 0;

    tableRowStart=45;

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
    initializePDFLibraries() {
        this.jsPDFInitialized = true;
        try {
            loadScript(this, JS_PDF)
            .then(() => loadScript(this, jsPDFAutoTable))
            .then(() => { this.isLoading = false; })
        } catch (error) {
            console.error('Error loading PDF libraries:', error);
            this.loadError = true;
            this.isLoading = false;
            this.showToast('Error', 'Failed to load PDF libraries', 'error');
        }
    }

    /**
     * Helper — parse "YYYY-MM-DD" or ISO strings as a local Date (so no UTC shift)
     */
    parseDateAsLocal(dateStr) {
        if (!dateStr) return null;
        if (dateStr instanceof Date) return new Date(dateStr.getFullYear(), dateStr.getMonth(), dateStr.getDate());

        const ymd = String(dateStr).split('T')[0].split(' ')[0];
        const parts = ymd.split('-');
        if (parts.length < 3) return null;
        const year = parseInt(parts[0], 10);
        const month = parseInt(parts[1], 10) - 1;
        const day = parseInt(parts[2], 10);
        return new Date(year, month, day);
    }

    /**
     * Helper — format a Date (local) into "YYYY-MM-DD"
     */
    formatYMD(date) {
        const y = date.getFullYear();
        const m = String(date.getMonth() + 1).padStart(2, '0');
        const d = String(date.getDate()).padStart(2, '0');
        return `${y}-${m}-${d}`;
    }

    /**
     * Generate normalized "YYYY-MM-DD" from whatever Salesforce returned for the line item date.
     * Handles "YYYY-MM-DD", "YYYY-MM-DDTHH:mm:ssZ", Date objects, etc.
     */
    extractYMDFromSFDate(sfDate) {
        if (!sfDate) return '';
        if (sfDate instanceof Date) return this.formatYMD(sfDate);
        return String(sfDate).split('T')[0].split(' ')[0];
    }

    /**
     * @description Handles click event for generating timesheet
     */
    async handleClick() {
        if (!this.validateDates()) return;

        try {
            this.isGeneratingPDF = true;

            this.totalDuration = 0;
            this.totalDays = 0;

            // Parallel data fetching
            const [employeeData, lineItems] = await Promise.all([
                this.fetchEmployeeData(),
                this.fetchTimesheetData()
            ]);

            if (!lineItems?.length) {
                this.showToast('Warning', 'No Timesheet Items found for the selected period.', 'warning');
                return;
            }

            this.Employee = employeeData;

            this.processTimesheetData(lineItems);
            
            await this.handleGeneratePDF();
            
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

        // Parse as local dates to avoid timezone shifts
        this.sd = this.parseDateAsLocal(startDate.value);
        this.ed = this.parseDateAsLocal(endDate.value);

        if (!this.sd || !this.ed) {
            this.showToast('Warning', 'Invalid date format', 'warning');
            return false;
        }

        if (this.ed < this.sd) {
            this.showToast('Warning', 'End date must be after start date', 'warning');
            return false;
        }

        // Use local-format YYYY-MM-DD (avoid toISOString which converts to UTC)
        this.startDate = this.formatYMD(this.sd);
        this.endDate = this.formatYMD(this.ed);

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
                startDate: this.startDate,
                endDate: this.endDate
            });
        } catch (error) {
            console.error('Error fetching timesheets:', error);
            throw error;
        }
    }
	
    /**
     * @description Processes timesheet data
     */
    processTimesheetData(lineItems) {
        this.processLineItems(lineItems);
        this.addTotalRow();
    }

    /**
     * @description Processes timesheet line items
     * (Rewritten to use local-midnight Date creation and normalized matching to avoid timezone shifts)
     */
    processLineItems(lineItems) {
        const startDateLocal = this.parseDateAsLocal(this.startDate);
        const endDateLocal = this.parseDateAsLocal(this.endDate);
        if (!startDateLocal || !endDateLocal) {
            this.TimesheetLineItems = [];
            return;
        }

        const tempLineItems = [];
        const dateCursor = new Date(startDateLocal); // local midnight

        while (dateCursor <= endDateLocal) {
            const yyyyMmDd = this.formatYMD(dateCursor);
            tempLineItems.push({
                dbt__Date__c: yyyyMmDd,
                duration: "0",
                Day: this.weekdays[dateCursor.getDay()]
            });
            
            dateCursor.setDate(dateCursor.getDate() + 1);
            this.totalDays++;
        }

        // Normalize incoming items to YYYY-MM-DD before matching
        const normalizedItems = (lineItems || []).map(item => ({
            ymd: this.extractYMDFromSFDate(item.dbt__Date__c),
            duration: item.duration != null ? String(item.duration) : "0"
        }));

        tempLineItems.forEach(row => {
            const match = normalizedItems.find(it => it.ymd === row.dbt__Date__c);
            if (match) {
                row.duration = match.duration;
            }
        });

        // Sum totalDuration from original lineItems (safe parse)
        this.totalDuration = (lineItems || []).reduce((acc, it) => acc + (parseFloat(it.duration) || 0), 0);

        this.TimesheetLineItems = tempLineItems;
    }

    /**
     * @description Adds total row
     */
    addTotalRow() {
        this.TimesheetLineItems.push({
            Day: "Total",
            dbt__Date__c: this.totalDays.toString(),
            duration: this.totalDuration.toString()
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
            doc.save(`${this.Employee?.Name || "Unknown Contractor"}_Timesheet_${this.startDate}_${this.endDate}.pdf`);
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
        const clientmanagerName = this.Employee?.dbt__Client_Manager__r?.Name || "Unknown Manager";
        const clientmanagerEmail = this.Employee?.dbt__Client_Manager_email__c || "No Email Provided";

        const pic = new Image();
        pic.src = imageLogo;

        doc.setFontSize(22);
        doc.setTextColor(0, 56, 101);
        doc.text(`Timesheet_${this.startDate || 'NA'}_${this.endDate || 'Na'}`, 18, this.tableRowStart - 20); 
        doc.setFontSize(12);
        doc.setTextColor(0, 0, 0);

        doc.setDrawColor(123, 0, 166);
        doc.line(15, 34, 195, 34);
        doc.line(15, 35, 195, 35);

        doc.text("Name of Contractor: " + contractorName, 15, this.tableRowStart);
        doc.addImage(pic, 165, 2, 30, 30);
        doc.text("Client: " + this.Client, 15, this.tableRowStart + 10);
        doc.text("Name of Manager: " + clientmanagerName, 15, this.tableRowStart + 20);
        doc.text("Period Ending: " + this.endDate, 15, this.tableRowStart + 30);
        doc.text("Please email Completed & Signed to: " + clientmanagerEmail, 15, this.tableRowStart + 40);
    }

    /**
     * @description Adds table to PDF
     */
    addTable(doc) {
        const footer = [this.TimesheetLineItems.pop()];
        const columns = [
            { header: "Day", dataKey: "Day" },
            { header: "Date", dataKey: "dbt__Date__c" },
            { header: "Hours_Worked", dataKey: "duration" }
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
            startY: this.tableRowStart + 50,
            // alternateRowStyles: { fillColor: [245, 245, 245] },
            headStyles: {
                fillColor: [0, 56, 101],
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
                fillColor: [157, 196, 75],
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
            cell.styles.fillColor = [255, 207, 170];
        }

        if (day === 'Saturday' || day === 'Sunday') {
            cell.styles.fillColor = [230, 230, 230];
        }
    }

    get generateButtonLabel() {
        return this.isGeneratingPDF ? 'Generating PDF...' : 'Generate PDF';
    }

    get isButtonDisabled() {
        return this.isGeneratingPDF || this.isLoading;
    }
}