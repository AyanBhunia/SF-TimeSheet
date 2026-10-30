/**
 * @file dashboardContributionChart.js
 * @description LWC for displaying a matrix chart visualization of timesheet data
 */

import { LightningElement, api, track, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import ChartJS from '@salesforce/resourceUrl/jsChart';
import jsChartMatrix from '@salesforce/resourceUrl/jsChartMatrix';
import { getChartData } from 'c/dashboardSharedData';
import USER_ID from '@salesforce/user/Id';

// LMS imports for handling user selection
import { subscribe, MessageContext } from 'lightning/messageService';
import SELECTED_USER_CHANNEL from '@salesforce/messageChannel/UserChannel__c';

export default class dashboardContributionChart extends LightningElement {
    @track chartData;

    // Chart configuration
    chart;
    isChartJsInitialized = false;
    year = new Date().getFullYear(); // Default to current year

    // LMS configuration
    @wire(MessageContext)
    messageContext;

    subscription = null;
    selectedUserId = USER_ID; // Initialize with current user's ID

    /**
     * @description Lifecycle hook when component is inserted into the DOM
     */
    connectedCallback() {
        this.subscribeToMessageChannel();
    }

    /**
     * @description Subscribes to LMS channel for user selection updates
     */
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

    /**
     * @description Handles incoming LMS messages
     * @param {Object} message - Message containing selected user ID
     */
    handleMessage(message) {
        this.selectedUserId = message.selectedUserId;
        this.initializeChart();
    }

    /**
     * @description Lifecycle hook when component is rendered
     */
    renderedCallback() {
        if (this.isChartJsInitialized) {
            return;
        }
        this.isChartJsInitialized = true;

        // Load required Chart.js libraries
        loadScript(this, ChartJS)
            .then(() => loadScript(this, jsChartMatrix))
            .then(() => this.initializeChart())
            .catch(error => {
                console.log('Error loading Script');
            });
    }

    /**
     * @description Initializes the chart with data for selected user
     */
    initializeChart() {
        if (this.selectedUserId) {
            getChartData(this.selectedUserId)
                .then(data => {
                    this.chartData = data;
                    this.showChart();
                })
                .catch(error => {
                    console.log('Error getting chart data');
                });
        }
    }

    /**
     * @description Renders or updates the chart visualization
     */
    showChart() {
        const ctx = this.template.querySelector('canvas').getContext('2d');
        
        // Handle no data scenario
        if(this.chartData == 0) {
            this.template.querySelector('.slds-m-around_medium').style.display = 'none';
            return;
        }
        this.template.querySelector('.slds-m-around_medium').style.removeProperty('display');

        // Prepare data for the chart
        const graphdata = this.prepareGraphData();

        // Update existing chart or create new one
        if(this.chart){
            this.chart.data.datasets[0].data = graphdata;
            this.chart.update();
        }
        else{
            // Chart configuration object
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
                    animation: { duration: 0 },
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
                            ticks: {
                                stepSize: 1,
                                maxRotation: 0,
                                autoSkip: true,
                                callback: (value) => {
                                    // Use UTC-based date for tick label (start of that week)
                                    const ts = Date.UTC(this.year, 0, 1) + (value - 1) * 7 * 86400000;
                                    const d = new Date(ts);
                                    return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
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

    /**
     * @description Prepares data for the matrix chart visualization
     * @returns {Array} Formatted data points for the chart
     *
     * NOTE: This function was adjusted to use UTC-based parsing and iteration so local timezone
     * doesn't shift dates. It preserves how chartData is consumed (no change to incoming structure).
     */
    prepareGraphData() {
        const { dayItems } = this.chartData;

        // Helper arrays & functions for consistent UTC formatting/parsing
        const shortDayNames = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
        const shortMonthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        const pad = (n) => (n < 10 ? '0' + n : String(n));

        // Try to parse incoming day string like "Mon Jan 01 2024" into a UTC Date (midnight UTC)
        const parseDayStringToUTC = (str) => {
            if (!str || typeof str !== 'string') {
                const fallback = new Date(str);
                return new Date(Date.UTC(fallback.getUTCFullYear(), fallback.getUTCMonth(), fallback.getUTCDate()));
            }
            const parts = str.trim().split(/\s+/); // expect [DayName, Month, DD, YYYY]
            if (parts.length === 4) {
                const monthIndex = shortMonthNames.indexOf(parts[1]);
                const dayNum = parseInt(parts[2], 10);
                const yearNum = parseInt(parts[3], 10);
                if (monthIndex >= 0 && !isNaN(dayNum) && !isNaN(yearNum)) {
                    return new Date(Date.UTC(yearNum, monthIndex, dayNum));
                }
            }
            // fallback to Date parsing then normalize to UTC midnight
            const dt = new Date(str);
            return new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate()));
        };

        const formatDateKeyUTC = (dateObj) => {
            const d = dateObj instanceof Date ? dateObj : new Date(dateObj);
            return `${shortDayNames[d.getUTCDay()]} ${shortMonthNames[d.getUTCMonth()]} ${pad(d.getUTCDate())} ${d.getUTCFullYear()}`;
        };

        // Filter data for current year using UTC-aware parsing
        const dataItems = dayItems.filter(item => {
            const parsed = parseDayStringToUTC(item.day);
            return parsed.getUTCFullYear() === this.year;
        });

        // Build a map keyed by UTC-formatted day string (matching sharedData's format)
        const dateToDuration = {};
        dataItems.forEach(item => {
            const parsed = parseDayStringToUTC(item.day);
            const key = formatDateKeyUTC(parsed);
            dateToDuration[key] = item.duration;
        });

        // Setup UTC date range for the year
        const startTs = Date.UTC(this.year, 0, 1);
        const endTs = Date.UTC(this.year, 11, 31);

        // firstMonday calculation (UTC)
        let firstMondayTs = null;
        const computeFirstMonday = () => {
            if (firstMondayTs !== null) return firstMondayTs;
            const jan1Ts = Date.UTC(this.year, 0, 1);
            const jan1Day = new Date(jan1Ts).getUTCDay(); // 0 (Sun) - 6 (Sat)
            if (jan1Day === 1) {
                firstMondayTs = jan1Ts;
            } else {
                const daysUntilNextMonday = (8 - jan1Day) % 7;
                firstMondayTs = jan1Ts + daysUntilNextMonday * 86400000;
            }
            return firstMondayTs;
        };

        const getMondayBasedWeekNumber = (dateTs) => {
            const fm = computeFirstMonday();
            return Math.floor((dateTs - fm) / 604800000) + 1;
        };

        // Generate data points iterating by UTC midnight increments
        const graphdata = [];
        for (let ts = startTs; ts <= endTs; ts += 86400000) {
            const dUTC = new Date(ts);
            const dateKey = formatDateKeyUTC(dUTC);
            const duration = dateToDuration[dateKey] || 0;
            let dayOfWeek = dUTC.getUTCDay(); // 0 (Sun) - 6 (Sat)
            dayOfWeek = dayOfWeek === 0 ? 7 : dayOfWeek; // convert so Monday=1 ... Sunday=7

            const weekNumber = getMondayBasedWeekNumber(ts);

            graphdata.push({
                x: weekNumber,
                y: dayOfWeek,
                d: dateKey,
                v: duration
            });
        }

        return graphdata;
    }
}