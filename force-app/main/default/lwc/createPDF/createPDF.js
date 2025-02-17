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
     * @description Processes timesheet line items
     */
    processLineItems(lineItems) {
        this.TimesheetLineItems = lineItems.map(element => ({
            ...element,
            duration: element.duration.toString(),
            Day: this.weekdays[new Date(element.dbt__Date__c).getDay()]
        }));
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
        
        doc.save(`timesheet_${this.Timesheet?.dbt__End_Date__c || 'generated'}.pdf`);
    }

    /**
     * @description Adds header to PDF
     */
    addHeader(doc) {
        const contractorName = this.Timesheet?.dbt__Employee__r?.Name || "Unknown Contractor";
        const clientManagerName = this.Timesheet?.dbt__Employee__r?.Client_Manager__r?.Name || "Unknown Manager";
        const clientManagerEmail = this.Timesheet?.dbt__Employee__r?.Client_Manager_email__c || "No Email Provided";
        const fortnightEnding = this.Timesheet?.dbt__End_Date__c || "Unknown Date";
        const billableHours = this.Timesheet?.dbt__Billable_Hours__c || "0";
        const totalHours = this.Timesheet?.dbt__Total_Hours__c || "0";

        const pic = new Image();
        pic.src = imageLogo;

        doc.text("Name of Contractor: " + contractorName, 10, 10);
        doc.addImage(pic, 190, 2, 15, 15);
        doc.text("Digital Biz Tech", 148, 10);
        doc.text("Fortnight Ending: " + fortnightEnding, 10, 20);
        doc.text("Name of Manager: " + clientManagerName, 10, 30);
        doc.text("Manager Email: " + clientManagerEmail, 10, 40);
        doc.text("Billable Hours: " + billableHours, 10, 50);
        doc.text("Total Hours: " + totalHours, 10, 60);
    }

    /**
     * @description Adds table to PDF
     */
    addTable(doc) {
        const columns = [
            { header: 'Day', dataKey: 'Day' },
            { header: 'Date', dataKey: 'dbt__Date__c' },
            { header: 'Hours Worked', dataKey: 'duration' }
        ];

        doc.autoTable({
            startY: 70,
            columns: columns,
            body: this.TimesheetLineItems,
            theme: 'grid',
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
            didParseCell: (data) => {
                const { row, column } = data;
                if (row.raw?.Day === 'Saturday' || row.raw?.Day === 'Sunday') {
                    data.cell.styles.fillColor = [240, 240, 240];
                }
            }
        });
    }

    get generateButtonLabel() {
        return this.isGeneratingPDF ? 'Generating PDF...' : 'Generate PDF';
    }

    get isButtonDisabled() {
        return this.isGeneratingPDF || this.isLoading;
    }
}