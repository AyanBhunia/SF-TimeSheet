import getTimesheetRecords from '@salesforce/apex/GetTimesheet.getTimesheetRecords';
import getTimesheetLineItemsRecords from '@salesforce/apex/GetTimesheetLineItems.getTimesheetLineItemsRecords';
import imageLogo from '@salesforce/resourceUrl/dbtLogo';
import JS_PDF from '@salesforce/resourceUrl/jsPDF';
import jsPDFAutoTable from '@salesforce/resourceUrl/jsPdfAutotable';
import { loadScript } from 'lightning/platformResourceLoader';
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class PdfGenerator extends LightningElement {
    @api recordId;
    @track isGeneratingPDF = false;

    // Private properties
    Timesheet;
    TimesheetLineItems = [];
    weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    tableRowStart = 45;

    // PDF Generation states
    jsPDFInitialized = false;
    loadError = false;
    isLoading = true;

    /**
     * @description Shows toast message
     */
    showToast(title, message, variant) {
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
     * @description Handles generate PDF button click
     */
    async handleClick() {
        if (!this.validatePDFGeneration()) return;

        try {
            this.isGeneratingPDF = true;
            await this.generateData();
            this.showToast('Success', 'PDF generated successfully', 'success');
        } catch (error) {
            console.error('Error generating PDF:', error);
            this.showToast('Error', 'Failed to generate PDF', 'error');
        } finally {
            this.isGeneratingPDF = false;
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
        return true;
    }

    /**
     * @description Generates data and creates PDF
     */
    async generateData() {
        try {
            const timesheetData = await getTimesheetRecords({ recID: this.recordId });
            this.Timesheet = timesheetData;

            const lineItems = await getTimesheetLineItemsRecords({ recId: this.recordId });
            this.processLineItems(lineItems);
            
            await this.handleGeneratePDF();
        } catch (error) {
            console.error('Error generating data:', error);
            throw error;
        }
    }

    /**
     * Helper — parse "YYYY-MM-DD" or ISO strings as a local Date (so no UTC shift)
     */
    parseDateAsLocal(dateStr) {
        if (!dateStr) return null;
        // If it's already a Date instance, construct a local-midnight date from its Y/M/D
        if (dateStr instanceof Date) return new Date(dateStr.getFullYear(), dateStr.getMonth(), dateStr.getDate());

        // If string (ISO or "YYYY-MM-DD"), extract YYYY-MM-DD safely
        const ymd = String(dateStr).split('T')[0].split(' ')[0];
        const parts = ymd.split('-');
        if (parts.length < 3) return null;
        const year = parseInt(parts[0], 10);
        const month = parseInt(parts[1], 10) - 1; // monthIndex
        const day = parseInt(parts[2], 10);
        return new Date(year, month, day); // local midnight
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
     * @description Processes timesheet line items
     * (Rewritten to use local-midnight Date creation to avoid timezone shifts)
     */
    processLineItems(lineItems) {
        const startDateLocal = this.parseDateAsLocal(this.Timesheet.dbt__Start_Date__c);
        const endDateLocal = this.parseDateAsLocal(this.Timesheet.dbt__End_Date__c);
        if (!startDateLocal || !endDateLocal) {
            this.TimesheetLineItems = [];
            return;
        }

        const tempLineItems = [];
        const dateCursor = new Date(startDateLocal); // local

        while (dateCursor <= endDateLocal) {
            const yyyyMmDd = this.formatYMD(dateCursor);
            tempLineItems.push({
                dbt__Date__c: yyyyMmDd,
                duration: "0",
                Day: this.weekdays[dateCursor.getDay()]
            });
            dateCursor.setDate(dateCursor.getDate() + 1); // increments local day
        }

        // Normalize incoming items to YYYY-MM-DD before matching
        const normalizedItems = (lineItems || []).map(item => ({
            ymd: this.extractYMDFromSFDate(item.dbt__Date__c),
            duration: item.duration != null ? String(item.duration) : "0"
        }));

        tempLineItems.forEach(row => {
            const found = normalizedItems.find(it => it.ymd === row.dbt__Date__c);
            if (found) {
                row.duration = found.duration;
            }
        });

        this.TimesheetLineItems = tempLineItems;
    }

    /**
     * @description Generates PDF
     */
    async handleGeneratePDF() {
        const doc = new window.jspdf.jsPDF({
            orientation: 'portrait',
            unit: 'mm',
            format: 'a4'
        });

        this.addHeader(doc);
        this.addTable(doc);

        doc.save(`${this.Timesheet?.dbt__Employee__r?.Name || "Unknown Contractor"}_Timesheet_${this.Timesheet?.dbt__End_Date__c || 'generated'}.pdf`);
    }

    /**
     * @description Adds header to PDF
     */
    addHeader(doc) {
        const contractorName = this.Timesheet?.dbt__Employee__r?.Name || "Unknown Contractor";
        const clientManagerName = this.Timesheet?.dbt__Employee__r?.dbt__Client_Manager__r?.Name || "Unknown Manager";
        const clientManagerEmail = this.Timesheet?.dbt__Employee__r?.dbt__Client_Manager_email__c || "No Email Provided";
        const fortnightEnding = this.Timesheet?.dbt__End_Date__c || "Unknown Date";
        const billableHours = this.Timesheet?.dbt__Billable_Hours__c || "0";
        const totalHours = this.Timesheet?.dbt__Total_Hours__c || "0";

        const pic = new Image();
        pic.src = imageLogo;

        doc.setFontSize(22);
        doc.setTextColor(0, 56, 101);
        doc.text(`Timesheet_${this.Timesheet?.dbt__Start_Date__c || 'NA'}_${this.Timesheet?.dbt__End_Date__c || 'Na'}`, 18, this.tableRowStart - 20); 
        doc.setFontSize(12);
        doc.setTextColor(0, 0, 0);

        doc.setDrawColor(123, 0, 166);
        doc.line(15, 34, 195, 34);
        doc.line(15, 35, 195, 35);
        
        doc.text("Name: " + contractorName, 15, this.tableRowStart);
        doc.addImage(pic, 165, 2, 30, 30);
        doc.text("Period Ending: " + fortnightEnding, 15, this.tableRowStart + 10);
        doc.text("Name of Manager: " + clientManagerName, 15, this.tableRowStart + 20);
        doc.text("Manager Email: " + clientManagerEmail, 15, this.tableRowStart + 30);
        doc.text("Billable Hours: " + billableHours, 15, this.tableRowStart + 40);
        doc.text("Total Hours: " + totalHours, 15, this.tableRowStart + 50);
    }

    /**
     * @description Adds table to PDF
     */
    addTable(doc) {
        const columns = [
            { header: 'Day', dataKey: 'Day' },
            { header: 'Date', dataKey: 'dbt__Date__c' },
            { header: 'Hours_Worked', dataKey: 'duration' }
        ];

        doc.autoTable({
            startY: this.tableRowStart + 60,
            columns: columns,
            body: this.TimesheetLineItems,
            theme: 'grid',
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