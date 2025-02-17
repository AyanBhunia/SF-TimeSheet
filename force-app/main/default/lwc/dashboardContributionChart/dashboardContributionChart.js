// chartTwo.js
import { LightningElement, api, track, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import ChartJS from '@salesforce/resourceUrl/jsChart';
import jsChartMatrix from '@salesforce/resourceUrl/jsChartMatrix';
import { getChartData } from 'c/dashboardSharedData';
import USER_ID from '@salesforce/user/Id';

// LMS imports
import { subscribe, MessageContext } from 'lightning/messageService';
import SELECTED_USER_CHANNEL from '@salesforce/messageChannel/SelectedUserChannel__c';

export default class ChartTwo extends LightningElement {
    @track chartData;

    chart;
    isChartJsInitialized = false;
    year = new Date().getFullYear(); // Default to current year

    // LMS
    @wire(MessageContext)
    messageContext;

    subscription = null;
    selectedUserId = USER_ID; // Set to current user by default

    connectedCallback() {
        // Subscribe to message channel
        this.subscribeToMessageChannel();
    }

    subscribeToMessageChannel() {
        if (this.subscription) {
            return;
        }
        this.subscription = subscribe(
            this.messageContext,
            SELECTED_USER_CHANNEL,
            (message) => this.handleMessage(message)
        );
    }

    handleMessage(message) {
        this.selectedUserId = message.selectedUserId;
        console.log('Received selected user ID:', this.selectedUserId);

        // Re-initialize the chart with the new user ID
        this.initializeChart();
    }

    renderedCallback() {
        if (this.isChartJsInitialized) {
            return;
        }
        this.isChartJsInitialized = true;

        // Load Chart.js script
        loadScript(this, ChartJS)
            .then(() => {
                return loadScript(this, jsChartMatrix);
            })
            .then(() => {
                this.initializeChart();
            })
            .catch(error => {
                console.error('Error loading ChartJS', error);
            });
    }

    initializeChart() {
        console.log("start 2",this.selectedUserId);
        if (this.selectedUserId) {
            getChartData(this.selectedUserId)
                .then(data => {
                    console.log("got data 2");
                    console.log("data",data);
                    this.chartData = data;
                    this.showChart();
                })
                .catch(error => {
                    console.error('Error fetching chart data:', error);
                });
        }
    }

    showChart() {
        const ctx = this.template.querySelector('canvas').getContext('2d');
        
        if(this.chartData == 0) {
            this.template.querySelector('.slds-m-around_medium').style.display = 'none';
            return;
        }
        this.template.querySelector('.slds-m-around_medium').style.removeProperty('display');

        // Prepare data for the chart
        const graphdata = this.prepareGraphData();

        console.log("graphdata",graphdata);

        if(this.chart){
            //update existing chart data
            this.chart.data.datasets[0].data = graphdata;
            this.chart.update();
        }
        else{
            // Create the chart
            this.chart = new Chart(ctx, {
                type: 'matrix',
                data: {
                    datasets: [{
                        label: 'Contributions',
                        data: graphdata,
                        backgroundColor: (context) => {
                            const value = context.dataset.data[context.dataIndex].v;
                            const alpha = value === 0 ? 0.1 
                                        : value < 4 ? 0.3 
                                        : value < 7 ? 0.6 
                                        : value < 10 ? 0.9 
                                        : 1;
                            return `rgba(101, 129, 71, ${alpha})`;
                        },
                        borderColor: (context) => {
                            const value = context.dataset.data[context.dataIndex].v;
                            const alpha = value === 0 ? 0.1 
                                        : value < 4 ? 0.3 
                                        : value < 7 ? 0.6 
                                        : value < 10 ? 0.9 
                                        : 1;
                            return `rgba(101, 129, 71, ${alpha * 0.7})`;
                        },
                        borderWidth: 1,
                        // hoverBackgroundColor: 'rgba(255, 255, 0, 0.8)',
                        // hoverBorderColor: 'rgba(154, 205, 50, 0.8)',
                        width: (context) => {
                            const area = context.chart.chartArea;
                            return area ? (area.right - area.left) / 53 - 2 : 0;
                        },
                        height: (context) => {
                            const area = context.chart.chartArea;
                            return area ? (area.bottom - area.top) / 7 - 2 : 0;
                        }
                    }]
                },
                options: {
                    animation: {
                        duration: 0  // disable animations
                    },
                    aspectRatio: 5,
                    plugins: {
                        legend: { display: false },
                        tooltip: {
                            enabled: true,
                            displayColors: false,
                            callbacks: {
                                title: () => '',
                                label: (context) => {
                                    const v = context.dataset.data[context.dataIndex];
                                    return [`Date: ${v.d}`, `Duration: ${v.v}`];
                                }
                            }
                        }
                    },
                    scales: {
                        y: {
                            type: 'linear',
                            offset: true,
                            min: 1,
                            max: 7,
                            position: 'left',
                            ticks: {
                                stepSize: 1,
                                maxRotation: 0,
                                autoSkip: true,
                                callback: value => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][value - 1],
                                font: { size: 11 }
                            },
                            grid: { display: false, drawBorder: false, tickLength: 0 }
                        },
                        x: {
                            type: 'linear',
                            position: 'bottom',
                            offset: true,
                            min: 1,
                            max: 53,
                            // reverse: true,
                            ticks: {
                                stepSize: 1,
                                maxRotation: 0,
                                autoSkip: true,
                                callback: (value) => {
                                    return new Date(this.year, 0, 1 + (value - 1) * 7)
                                        .toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
                                },
                                font: { size: 11 }
                            },
                            grid: { display: false, drawBorder: false, tickLength: 0 }
                        }
                    },
                    layout: { padding: { top: 10 } }
                }
            });
        }
    }

    prepareGraphData() {
        const { dayItems } = this.chartData;

        // Filter data for the selected year
        const dataItems = dayItems.filter(item => {
            const itemYear = new Date(item.day).getFullYear();
            return itemYear === this.year;
        });

        // Initialize an empty array for graphdata
        const graphdata = [];

        // Create a mapping from date strings to durations for quick lookup
        const dateToDuration = {};

        // Populate the dateToDuration map with data from dataItems
        dataItems.forEach(item => {
            dateToDuration[item.day] = item.duration;
        });

        // Get the first and last day of the year
        const startDate = new Date(this.year, 0, 1);
        const endDate = new Date(this.year, 11, 31);

        let firstMonday = null;

        const getMondayBasedWeekNumber = (date) => {
            const jan1 = new Date(date.getFullYear(), 0, 1);
            const jan1Day = jan1.getDay(); // Day of the week (0 = Sunday, 1 = Monday, ..., 6 = Saturday)

            // Find the first Monday of the year
            if (!firstMonday) {
                firstMonday = jan1Day === 1 ? jan1 : new Date(jan1.getTime() + ((8 - jan1Day) % 7) * 86400000);
            }

            // Calculate the week number (Monday-Sunday basis)
            return Math.floor((date - firstMonday) / 604800000) + 1;
        };

        // Loop over each day of the year
        for (let d = new Date(startDate); d <= endDate; d.setDate(d.getDate() + 1)) {
            // Get the formatted date string
            const dateKey = d.toDateString();

            // Get the duration if the date exists in dataItems, else 0
            const duration = dateToDuration[dateKey] || 0;

            // Get the week number and day of the week
            const weekNumber = getMondayBasedWeekNumber(new Date(d));
            let dayOfWeek = d.getDay();
            dayOfWeek = dayOfWeek === 0 ? 7 : dayOfWeek; // 0 = Sunday, 1 = Monday, ..., 6 = Saturday

            // Push the data point to graphdata
            graphdata.push({
                x: weekNumber,
                y: dayOfWeek,
                d: dateKey, // The date string in 'YYYY-MM-DD' format
                v: duration // The duration value
            });
        }

        return graphdata;
    }
}