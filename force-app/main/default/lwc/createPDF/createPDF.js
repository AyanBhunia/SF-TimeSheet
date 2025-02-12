import getTimesheetRecords from '@salesforce/apex/GetTimesheet.getTimesheetRecords';
import getTimesheetLineItemsRecords from '@salesforce/apex/GetTimesheetLineItems.getTimesheetLineItemsRecords';
import image from '@salesforce/resourceUrl/dbtLogo';
import JS_PDF from '@salesforce/resourceUrl/jsPDF';
import { loadScript } from 'lightning/platformResourceLoader';
import { LightningElement, api } from 'lwc';

export default class PdfGenerator extends LightningElement {

	@api recordId; 

	Timesheet;

	TimesheetLineItems = [];

	headers = [
		{id: "Day",
			name: "Day",
			prompt: "Day",
			width: 65,
			align: "center",
			padding: 0},
		{id: "dbt__Date__c",
			name: "dbt__Date__c",
			prompt: "Date",
			width: 65,
			align: "center",
			padding: 0},
		{id: "duration",
			name: "duration",
			prompt: "Day Worked",
			width: 65,
			align: "center",
			padding: 0}
		
	];

	date;
	dayNumber;
	weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

	jsPDFInitialized = false;

	renderedCallback() {
		if (!this.jsPDFInitialized) {
			this.jsPDFInitialized = true;
			loadScript(this, JS_PDF)
				.then(() => {
					console.log('jsPDF library loaded successfully');
				})
				.catch((error) => {
					console.error('Error loading jsPDF library', error);
				});
		}
	}

	handleGeneratePDF() {
		if (this.jsPDFInitialized) {
			// Make sure to correctly reference the loaded jsPDF library.
			const doc = new window.jspdf.jsPDF();
			const pic = new Image();

			pic.src = image;

			// Define the content of the PDF.
			const contractorName = this.Timesheet?.dbt__Employee__r?.Name || "Unknown Contractor";
			const clientManagerName = this.Timesheet?.dbt__Employee__r?.Client_Manager__r?.Name || "Unknown Manager";
			const clientManagerEmail = this.Timesheet?.dbt__Employee__r?.Client_Manager_email__c || "No Email Provided";
			const fortnightEnding = this.Timesheet?.dbt__End_Date__c || "Unknown Date";
			const billableHours = this.Timesheet?.dbt__Billable_Hours__c || "0";
			const totalHours = this.Timesheet?.dbt__Total_Hours__c || "0";

			// Add content to the PDF.
			doc.text("Name of Contractor: " + contractorName, 10, 10);
			doc.addImage(pic, 190, 2, 15, 15);
			doc.text("Digital Biz Tech", 148, 10);
			doc.text("Fortnight Ending: " + fortnightEnding, 10, 20);
			doc.text("Name of Manager: " + clientManagerName, 10, 30);
			doc.text("Manager Email: " + clientManagerEmail, 10, 40);
			doc.text("Billable Hours: " + billableHours, 10, 50);
			doc.text("Total Hours: " + totalHours, 10, 60);

			doc.table(30, 80, this.TimesheetLineItems, this.headers, {autosize:true});

			//doc.table(10, 80, this.testData, this.testHeader, {autosize: true});

			//doc.table(30, 30, this.Employee, this.headers, {autosize:true});

			// Save the PDF.
			doc.save('generated_pdf.pdf');
		} else {
			console.error('jsPDF library not initialized');
		}
	}

	generateData(){
		getTimesheetRecords({recID: this.recordId}).then(result =>{
			this.Timesheet = result;		
			getTimesheetLineItemsRecords({recId: this.recordId}).then(result => {
				this.TimesheetLineItems =  result;
	
				this.TimesheetLineItems.forEach(element => {
					element.duration = element.duration.toString();
					this.date = new Date(element.dbt__Date__c);
					this.dayNumber = this.date.getDay();
					element.Day = this.weekdays[this.dayNumber];
				});
				this.handleGeneratePDF();
			});
		});
	}

	createHeaders(keys) {
		var result = [];
		for (var i = 0; i < keys.length; i += 1) {
			result.push({
				id: keys[i],
				name: keys[i],
				prompt: keys[i],
				width: 65,
				align: "center",
				padding: 0
			});
		}
		return result;
	}
}