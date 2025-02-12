import getEmployee from '@salesforce/apex/GetEmployeeDetails.getEmployee';
import getTimesheetsLineItems from '@salesforce/apex/GetRangeOfTimesheetsLineItems.getTimesheetsLineItems';
import imageLogo from '@salesforce/resourceUrl/dbtLogo';
import JS_PDF from '@salesforce/resourceUrl/jsPDF';
import jsPDFAutoTable from '@salesforce/resourceUrl/jsPdfAutotable';
import { loadScript } from 'lightning/platformResourceLoader';
import { LightningElement, api } from 'lwc';

export default class CreateEmployeeTimesheet extends LightningElement {

    @api recordId;
	//fetching record Id of respective pages

    Employee;
	//contains employee details

    TimesheetLineItems;
	//contains timesheetline items

    sd;
	ed;
	date;
	startDate="No Start Date";
	endDate="No End Date";
	Client="";
	totalDurationAttendance=0;
	totalDurationAbsence=0;
	dayNumber;
	weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
	//to calculate day for respective date

    // to load the jsPDF library to the page
    jsPDFInitialized = false;
    loadError = false;
    isLoading = true; // To manage button state

    renderedCallback() {
        if (this.jsPDFInitialized) {
            return;
        }
        this.jsPDFInitialized = true;

        // Load jsPDF first
        loadScript(this, JS_PDF)
            .then(() => {
                console.log('jsPDF library loaded successfully');

                // // Verify jsPDF is available
                // if (window.jspdf) {
                //     console.log('jsPDF is available on window:', window.jspdf);
                // } else {
                //     throw new Error('jsPDF is not available on the window object.');
                // }

                // Now, load jsPDF-AutoTable
                return loadScript(this, jsPDFAutoTable);
            })
            .then(() => {
                console.log('jsPDF-AutoTable library loaded successfully');

                // Update state to indicate loading is complete
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading jsPDF libraries', error,error.toString());
                this.loadError = true;
                this.isLoading = false;
            });
    }

    handleGeneratePDF(){
		if (this.loadError) {
            console.error('Cannot generate PDF because scripts failed to load.');
            return;
        }

        if (this.isLoading) {
            console.warn('Scripts are still loading. Please wait.');
            return;
        }

        if (this.jsPDFInitialized) {
			const doc = new window.jspdf.jsPDF(); // Create a new jsPDF instance

			// Check if autoTable is available
			if (typeof doc.autoTable === 'function') {
				console.log('autoTable is available on jsPDF instance');
			} else {
				console.error('autoTable is NOT available on jsPDF instance');
			}
			
			const contractorName = this.Employee?.Name || "Unknown Contractor";
			const clientmanagerName = this.Employee?.Client_Manager__r?.Name || "Unknown Manager";
			const clientmanagerEmail = this.Employee?.Client_Manager_email__c || "No Email Provided";

			const pic = new Image();
			pic.src = imageLogo;

			// Add content to the PDF.
			doc.text("Name of Contractor: " + contractorName, 10, 10);
			doc.addImage(pic, 190, 2, 15, 15);
			doc.text("Client: " + this.Client, 10, 20);
			doc.text("Name of Manager: " + clientmanagerName, 10, 30);
			doc.text("Period Ending: " + this.endDate, 10, 40);
			// doc.text("Total Hours: " + this.totalDurationAttendance, 10, 40);
			doc.text("Please email Completed & Signed to: " + clientmanagerEmail, 10, 50);

			// Extract the last row for the footer
			const footer = [this.TimesheetLineItems.pop()]; // Footer as an array of one object

			// Define columns and rows for autoTable
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

			// Add autoTable
			doc.autoTable({
				theme: 'grid',
				columns: columns,
				body: rows,
				foot: footer,
				startY: 60,
				alternateRowStyles: {
					fillColor: [245, 245, 245], // Light grey for alternate rows
				},
				headStyles: {
					fillColor: [0, 172, 148], // Gradient green for the header
					textColor: [255, 255, 255], // White text
					fontSize: 13, // Larger font size
					fontStyle: 'bold', // Bold font
					cellPadding: 3,
					valign: 'middle',
					halign: 'center'
				},
				bodyStyles: {
					fontSize: 11,
					cellPadding: 2, // Add padding for better readability
					valign: 'middle',
					halign: 'center' 
				},
				footStyles: {
					fillColor: [128, 157, 60], // Green background for footer
					textColor: [255, 255, 255], // White text
					fontStyle: 'bold',
					fontSize: 12,
					cellPadding: 2.5,
					valign: 'middle',
					halign: 'center',
				},
				didParseCell: function (data) {
					const { row, cell, column } = data;
					const day = row.raw?.Day;
					const date = row.raw?.dbt__Date__c;
					const duration = row.raw?.duration;

					// Highlight individual cells where 'Hour Worked' is 0
					if (column.dataKey === 'duration' && duration === '0') {
						cell.styles.fillColor = [255, 179, 142]; // Red for cells with Hour Worked = 0
					}

					// Highlight rows based on conditions
					if (day === 'Saturday' || day === 'Sunday') {
						cell.styles.fillColor = [179, 200, 207]; // Light blue for weekends
					}
				},
			});

			// console.log(this.TimesheetLineItems);
                
            doc.save('generated_pdf.pdf');
        }else {
			console.error('jsPDF library not initialized');
		}
    }

    handleClick(){
        const startDate = this.template.querySelector('.start-date');
        const endDate = this.template.querySelector('.end-date');
		//fetch the date field element from html
		this.sd = new Date(startDate.value);
		this.ed = new Date(endDate.value);

// 		this.sd = new Date('2025-01-06T00:00:00Z');
// this.ed = new Date('2025-01-22T00:00:00Z');

		this.totalDurationAttendance = 0;
		this.totalDurationAbsence = 0;
		this.Client="";

        if(startDate.value && endDate.value){
		// if(true){
			if (this.ed >= this.sd) {
				// Fetch the Employee Details
				getEmployee({recID: this.recordId}).then(result => {
					this.Employee = result;

					this.Client = this.Employee.dbt__Project_Employees__r
						.map(el => el.dbt__Project_Name__c)
						.join(', ');
				
					// Fetch the Timesheet Line Items
					getTimesheetsLineItems({recID: this.recordId, startDate: this.sd, endDate: this.ed}).then(result => {
						this.TimesheetLineItems = result;
						console.log('TimesheetLineItems:', this.TimesheetLineItems);

						if (!this.TimesheetLineItems || this.TimesheetLineItems.length === 0) {
							alert('No Timesheet Items found for the selected period.');
						} else {

							// // Get the first and last date from the time sheet
							// this.startDate = this.TimesheetLineItems[0].dbt__Date__c;
							// this.endDate = this.TimesheetLineItems[this.TimesheetLineItems.length - 1].dbt__Date__c;

							// Create a Set of existing dates from TimesheetLineItems
							const dateSet = new Set(this.TimesheetLineItems.map(item => item.dbt__Date__c));

							// Format required fields in timesheet line items
							// Add week day name to all records
							this.TimesheetLineItems.forEach(element => {
								element.duration = element.duration.toString();
								this.date = new Date(element.dbt__Date__c);
								this.dayNumber = this.date.getDay();
								element.Day = this.weekdays[this.dayNumber];

								// caculate total duration for attendance and absence
								if(element.dbt__Type__c == "Attendance") {
									this.totalDurationAttendance += parseFloat(element.duration || 0);
								}
								else if(element.dbt__Type__c == "Absence") {
									this.totalDurationAbsence += parseFloat(element.duration || 0);
								}
							});

							// Generate missing dates based on the date range
							// let currentDate = new Date(this.startDate);
							// const finishDate = new Date(this.endDate); 
							let currentDate = this.sd;
							const finishDate = this.ed; 
							
							this.startDate = currentDate.toISOString().split("T")[0];
							this.endDate = finishDate.toISOString().split("T")[0];
							

							// Loop over the date range and find missing dates
							while (currentDate <= finishDate) {
								const formattedDate = currentDate.toISOString().split("T")[0]; // Format date as YYYY-MM-DD

								if (!dateSet.has(formattedDate)) {
									this.TimesheetLineItems.push({
										dbt__Date__c: formattedDate,
										duration: "0",  // Default duration for missing dates
										Day: this.weekdays[currentDate.getDay()], // Calculate weekday name
										dbt__Type__c: "Missing"
									});
								}

								// Move to the next date
								currentDate.setDate(currentDate.getDate() + 1);
							}

							// Sort the TimesheetLineItems by date and type
							this.TimesheetLineItems.sort((a, b) => {
								const dateA = new Date(a.dbt__Date__c);
								const dateB = new Date(b.dbt__Date__c);

								// First sort by date
								if (dateA < dateB) return -1;
								if (dateA > dateB) return 1;

								// If dates are the same, sort by type (Attendance first, then Absence)
								if (a.dbt__Type__c > b.dbt__Type__c) return -1;
								if (a.dbt__Type__c < b.dbt__Type__c) return 1;

								return 0;
							});

							// Append a total Attendance row
							this.TimesheetLineItems.push({
								Day: " ",
								dbt__Date__c: "Total",
								dbt__Type__c: "Attendance",
								duration: this.totalDurationAttendance.toString()
							});

							
							// genarate the pdf
							this.handleGeneratePDF();
						}

					}).catch(error => { 
						console.error('Error in TimesheetLine Items fetch :', error); 
					});

				}).catch(error => { 
					console.error('Error in Employee fetch :', error); 
				});
			} else {
				alert('End date must be greater than or equal to the start date.');
			}
        }
        else{
            alert('Please enter start and end date to generate Timesheets');
        }
    }
}