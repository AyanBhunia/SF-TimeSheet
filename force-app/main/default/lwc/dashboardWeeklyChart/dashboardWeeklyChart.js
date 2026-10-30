/**
 * @file dashboardWeeklyChart.js
 * @description LWC for displaying weekly timesheet data in bar chart format with navigation
 */

import { LightningElement, api, track, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import ChartJS from '@salesforce/resourceUrl/jsChart';
import { getChartData } from 'c/dashboardSharedData';
import USER_ID from '@salesforce/user/Id';

// LMS imports for handling user selection
import { subscribe, MessageContext } from 'lightning/messageService';
import SELECTED_USER_CHANNEL from '@salesforce/messageChannel/UserChannel__c';

export default class dashboardWeeklyChart extends LightningElement { 
    @track chartData;

    // Chart configuration properties
    attendanceChart;
    isChartJsInitialized = false;
    currentWeekIndex = 0; // Initialize to the latest week

    // LMS configuration
    @wire(MessageContext)
    messageContext;

    subscription = null;
    selectedUserId = USER_ID; // Default to current user

    // UTC helpers to avoid timezone shifts
    shortDayNames = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    shortMonthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    pad(n) { return n < 10 ? '0' + n : String(n); }

    /**
     * Parse a day string in format "Mon Jan 01 2024" (same as dashboardSharedData) to a Date at UTC midnight.
     * Fallback normalizes any input to UTC midnight.
     */
    parseDayStringToUTC(str) {
        if (!str || typeof str !== 'string') {
            const dt = new Date(str || Date.now());
            return new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate()));
        }
        const parts = str.trim().split(/\s+/); // expect [DayName, Month, DD, YYYY]
        if (parts.length === 4) {
            const monthIndex = this.shortMonthNames.indexOf(parts[1]);
            const dayNum = parseInt(parts[2], 10);
            const yearNum = parseInt(parts[3], 10);
            if (monthIndex >= 0 && !isNaN(dayNum) && !isNaN(yearNum)) {
                return new Date(Date.UTC(yearNum, monthIndex, dayNum));
            }
        }
        const dt = new Date(str);
        return new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate()));
    }

    formatDateKeyUTC(dateObj) {
        const d = dateObj instanceof Date ? dateObj : new Date(dateObj);
        return `${this.shortDayNames[d.getUTCDay()]} ${this.shortMonthNames[d.getUTCMonth()]} ${this.pad(d.getUTCDate())} ${d.getUTCFullYear()}`;
    }

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
     * @description Handles incoming LMS messages with selected user ID
     */
    handleMessage(message) {
        this.selectedUserId = message.selectedUserId;
        // Reset to latest week when user changes
        this.currentWeekIndex = 0;
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

        loadScript(this, ChartJS)
            .then(() => {
                this.initializeChart();
            })
            .catch(error => {
                console.error('Error loading ChartJS', error);
            });
    }

    /**
     * @description Initializes chart with data for selected user
     */
    initializeChart() {
        if (this.selectedUserId) {
            getChartData(this.selectedUserId)
                .then(data => {
                    this.chartData = data;
                    this.showChart();
                })
                .catch(error => {
                    console.error('Error fetching chart data:', error);
                });
        }
    }

    /**
     * @description Sets up and displays the chart
     */
    showChart() {
        const canvas = this.template.querySelector('canvas');
        const ctx = canvas.getContext('2d');

        // Handle no data scenario
        if(this.chartData == 0) {
            this.template.querySelector('.slds-m-around_medium').style.display = 'none';
            return;
        }
        this.template.querySelector('.slds-m-around_medium').style.removeProperty('display');

        // Setup navigation controls
        const prevButton = this.template.querySelector('[data-id="prevButton"]');
        const nextButton = this.template.querySelector('[data-id="nextButton"]');

        prevButton.addEventListener('click', this.handlePrevClick.bind(this));
        nextButton.addEventListener('click', this.handleNextClick.bind(this));

        this.renderChart(ctx);
    }

    /**
     * @description Navigation handlers for week selection
     */
    handlePrevClick() {
        this.currentWeekIndex = this.clampIndex(this.currentWeekIndex + 1, this.chartData.weekItems.length);
        const canvas = this.template.querySelector('canvas');
        const ctx = canvas.getContext('2d');
        this.renderChart(ctx);
    }

    handleNextClick() {
        this.currentWeekIndex = this.clampIndex(this.currentWeekIndex - 1, this.chartData.weekItems.length);
        const canvas = this.template.querySelector('canvas');
        const ctx = canvas.getContext('2d');
        this.renderChart(ctx);
    }

    /**
     * @description Ensures week index stays within bounds
     * @param {Number} index - Current index
     * @param {Number} length - Total number of weeks
     * @returns {Number} Clamped index value
     */
    clampIndex(index, length) {
        if (index < 0) {
            return length - 1;
        } else if (index >= length) {
            return 0;
        } else {
            return index;
        }
    }

    /**
     * @description Prepares data for chart visualization
     * @returns {Object} Formatted data for chart rendering
     */
    prepareChartData() {
        const { weekItems, getStartAndEndDate } = this.chartData;

        // Handle empty data case
        if (!weekItems || weekItems.length === 0) {
            return { datasets: [], labels: [], title: 'No Data' };
        }

        // Get week date range string and parse using UTC-safe parser
        let weekString = getStartAndEndDate(weekItems[this.currentWeekIndex].week);
        const [startStr, endStr] = weekString.split(' - ').map(s => s.trim());
        const startDateUTC = this.parseDayStringToUTC(startStr);
        const endDateUTC = this.parseDayStringToUTC(endStr);

        const title = `Week: ${weekString}`;

        // Initialize data structures
        let barDataProjects = new Map();
        let barDataAbsence = [];
        let barDataAttendance = [];
        let barDataDurations = [];
        let barLabels = [];
        let barTarget = [8, 8, 8, 8, 8, 8, 8]; // Daily target hours

        let dayData = [];

        // Process week data - day keys are already formatted strings from dashboardSharedData
        weekItems[this.currentWeekIndex].dates.forEach((date) => {
            dayData[date.day] = date;

            if (date.projects.size > 0) {
                date.projects.forEach((value, key) => {
                    if (!barDataProjects.has(key)) {
                        barDataProjects.set(key, []);
                    }
                });
            }
        });

        // Generate daily data points using UTC increments
        const msDay = 86400000;
        const startTs = Date.UTC(startDateUTC.getUTCFullYear(), startDateUTC.getUTCMonth(), startDateUTC.getUTCDate());
        const endTs = Date.UTC(endDateUTC.getUTCFullYear(), endDateUTC.getUTCMonth(), endDateUTC.getUTCDate());

        for (let ts = startTs; ts <= endTs; ts += msDay) {
            const dUTC = new Date(ts);
            const dayKey = this.formatDateKeyUTC(dUTC);
            barLabels.push(dayKey);

            // Process project data
            barDataProjects.forEach((value, key) => {
                if (dayData[dayKey] && dayData[dayKey].projects.has(key)) {
                    barDataProjects.get(key).push(dayData[dayKey].projects.get(key));
                } else {
                    barDataProjects.get(key).push(0);
                }
            });

            // Process attendance and absence data
            if (dayData[dayKey]) {
                barDataAbsence.push(dayData[dayKey].absence);
                barDataAttendance.push(dayData[dayKey].attendance);
                barDataDurations.push(dayData[dayKey].duration);
            } else {
                barDataAbsence.push(0);
                barDataAttendance.push(0);
                barDataDurations.push(0);
            }
        }

        return {
            barDataDurations: barDataDurations,
            barDataProjects: barDataProjects,
            barDataAttendance: barDataAttendance,
            barDataAbsence: barDataAbsence,
            barTarget: barTarget,
            barLabels: barLabels,
            title: title
        };
    }

    /**
     * @description Renders or updates the bar chart
     * @param {CanvasRenderingContext2D} ctx - Canvas context for chart rendering
     */
    renderChart(ctx) {
        // Chart color configuration
        const colors = ['#228B22', '#32CD32', '#00FF00', '#7CFC00', '#7FFF00', '#ADFF2F', '#98FB98', '#90EE90'];
        const borderColors = ['#2E8B2E', '#3CBF3C', '#00CC00', '#72D700', '#73D700', '#9BDB2F', '#8EE48E', '#7BDEA7'];

        // Get prepared chart data
        const {
            barDataDurations,
            barDataProjects,
            barDataAttendance,
            barDataAbsence,
            barTarget,
            barLabels,
            title
        } = this.prepareChartData();

        // Prepare project datasets
        const projectDatasets = [];
        let colorIndex = 1; // Start after attendance and absence colors

        // Create dataset for each project
        barDataProjects.forEach((dataArray, projectName) => {
            projectDatasets.push({
                label: projectName,
                data: dataArray,
                backgroundColor: colors[colorIndex % colors.length],
                borderColor: borderColors[colorIndex % borderColors.length],
                borderWidth: 1.5,
                stack: 'Stack 0',
                order: 1,
            });
            colorIndex++;
        });

        // Combine all datasets
        const datasets = [
            // Target line dataset
            {
                label: 'Target',
                data: barTarget,
                backgroundColor: '#808080',
                borderColor: '#808080',
                type: 'line',
                order: 0,
            },
            // Duration dataset
            {
                label: 'Duration',
                data: barDataDurations,
                backgroundColor: '#406b44',
                borderColor: '#406b44',
                borderWidth: 1,
                stack: 'Stack 0',
                order: 1,
                hidden: true,
            },
            // Attendance dataset
            {
                label: 'Attendance',
                data: barDataAttendance,
                backgroundColor: '#90EE90',
                borderColor: '#90EE90',
                borderWidth: 1,
                stack: 'Stack 0',
                order: 1,
                hidden: true,
            },
            // Absence dataset
            {
                label: 'Absence',
                data: barDataAbsence,
                backgroundColor: '#D91656',
                borderColor: '#D91656',
                borderWidth: 1,
                order: 2,
                stack: 'Stack 0',
            },
            ...projectDatasets,
        ];

        // Update existing chart or create new one
        if (this.attendanceChart) {
            // Update existing chart
            this.attendanceChart.data.labels = barLabels;
            this.attendanceChart.data.datasets = datasets;
            this.attendanceChart.options.plugins.title.text = title;
            this.attendanceChart.update();
        } else {
            // Create new chart with configuration
            this.attendanceChart = new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: barLabels,
                    datasets: datasets,
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: true,
                    plugins: {
                        title: {
                            display: true,
                            text: title,
                        },
                        legend: {
                            labels: {
                                /**
                                 * @description Generates custom legend labels
                                 * @param {Chart} chart - Chart instance
                                 * @returns {Array} Custom legend labels
                                 */
                                generateLabels: function (chart) {
                                    const original = Chart.defaults.plugins.legend.labels.generateLabels(chart);
                                    const customLabels = [];

                                    // Define main legend items
                                    const individualLabels = ['Target', 'Duration', 'Attendance', 'Absence'];

                                    // Generate individual legend items
                                    individualLabels.forEach((labelText) => {
                                        const datasetIndex = chart.data.datasets.findIndex(ds => ds.label === labelText);
                                        if (datasetIndex !== -1) {
                                            const dataset = chart.data.datasets[datasetIndex];
                                            const meta = chart.getDatasetMeta(datasetIndex);
                                            customLabels.push({
                                                text: labelText,
                                                fillStyle: dataset.backgroundColor,
                                                strokeStyle: dataset.borderColor,
                                                lineWidth: dataset.borderWidth,
                                                hidden: meta.hidden ?? dataset.hidden ?? false,
                                                datasetIndex: datasetIndex,
                                            });
                                        }
                                    });

                                    // Add Projects legend item
                                    const projectsDatasets = chart.data.datasets.slice(4);
                                    const projectsHidden = projectsDatasets.every(ds => {
                                        const idx = chart.data.datasets.indexOf(ds);
                                        return chart.getDatasetMeta(idx).hidden;
                                    });

                                    customLabels.push({
                                        text: 'Projects',
                                        fillStyle: 'rgba(128, 128, 128, 0.5)',
                                        strokeStyle: 'rgba(128, 128, 128, 1)',
                                        lineWidth: 1,
                                        hidden: projectsHidden,
                                        datasetIndex: 'projects',
                                    });

                                    return customLabels;
                                },
                            },
                            /**
                             * @description Handles legend item clicks
                             */
                            onClick: function (e, legendItem, legend) {
                                const chart = legend.chart;
                                const datasets = chart.data.datasets;
                                const clickedText = legendItem.text;
                                const isHidden = legendItem.hidden;

                                // Handle different legend item clicks
                                switch (clickedText) {
                                    case 'Target':
                                        // Toggle Target visibility
                                        const targetIndex = datasets.findIndex(ds => ds.label === 'Target');
                                        if (targetIndex !== -1) {
                                            const meta = chart.getDatasetMeta(targetIndex);
                                            meta.hidden = !meta.hidden;
                                            chart.update();
                                        }
                                        break;

                                    case 'Duration':
                                        // Toggle Duration view
                                        if (isHidden) {
                                            // Show Duration, hide others
                                            datasets.forEach((ds, idx) => {
                                                if (ds.label === 'Duration') {
                                                    chart.getDatasetMeta(idx).hidden = false;
                                                } else if (ds.label === 'Attendance' || ds.label === 'Absence') {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                } else if (idx >= 4) {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                }
                                            });
                                        } else {
                                            // Hide Duration, show Attendance/Absence
                                            datasets.forEach((ds, idx) => {
                                                if (ds.label === 'Duration') {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                } else if (ds.label === 'Attendance' || ds.label === 'Absence') {
                                                    chart.getDatasetMeta(idx).hidden = false;
                                                } else if (idx >= 4) {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                }
                                            });
                                        }
                                        chart.update();
                                        break;

                                    case 'Attendance':
                                        // Toggle Attendance view
                                        if (isHidden) {
                                            // Show Attendance/Absence, hide others
                                            datasets.forEach((ds, idx) => {
                                                if (ds.label === 'Attendance' || ds.label === 'Absence') {
                                                    chart.getDatasetMeta(idx).hidden = false;
                                                } else if (ds.label === 'Duration') {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                } else if (idx >= 4) {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                }
                                            });
                                        } else {
                                            // Hide Attendance/Absence, show Duration
                                            datasets.forEach((ds, idx) => {
                                                if (ds.label === 'Attendance' || ds.label === 'Absence') {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                } else if (ds.label === 'Duration') {
                                                    chart.getDatasetMeta(idx).hidden = false;
                                                } else if (idx >= 4) {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                }
                                            });
                                        }
                                        chart.update();
                                        break;

                                    case 'Projects':
                                        // Toggle Projects view
                                        if (isHidden) {
                                            // Show Projects/Absence, hide others
                                            datasets.forEach((ds, idx) => {
                                                if (idx >= 4) {
                                                    chart.getDatasetMeta(idx).hidden = false;
                                                }
                                                if (ds.label === 'Absence') {
                                                    chart.getDatasetMeta(idx).hidden = false;
                                                }
                                                if (ds.label === 'Duration' || ds.label === 'Attendance') {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                }
                                            });
                                        } else {
                                            // Hide Projects, show Attendance
                                            datasets.forEach((ds, idx) => {
                                                if (idx >= 4) {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                }
                                                if (ds.label === 'Attendance') {
                                                    chart.getDatasetMeta(idx).hidden = false;
                                                }
                                            });
                                        }
                                        chart.update();
                                        break;

                                    default:
                                        break;
                                }
                            },
                        },
                    },
                    // Axis configuration
                    scales: {
                        x: {
                            stacked: true,
                            title: {
                                display: true,
                                text: 'Days',
                            },
                            ticks: {
                                stepSize: 1,
                                maxRotation: 0,
                                minRotation: 0,
                                callback: (value) => {
                                    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
                                    // value is index into labels; use label string and parse it to UTC safely
                                    const label = this.attendanceChart ? this.attendanceChart.data.labels[value] : null;
                                    if (!label) return '';
                                    const parts = (label + '').trim().split(/\s+/); // [DayName, Month, DD, YYYY]
                                    if (parts.length === 4) {
                                        const monthIndex = this._component ? this._component.shortMonthNames.indexOf(parts[1]) : -1;
                                        // fallback: try parse via Date
                                    }
                                    // Parse using a safe approach similar to other helpers:
                                    // label format is "Mon Jan 01 2024" -> create UTC Date
                                    try {
                                        const parts2 = (label + '').trim().split(/\s+/);
                                        if (parts2.length === 4) {
                                            const monthIndex2 = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'].indexOf(parts2[1]);
                                            const dayNum2 = parseInt(parts2[2], 10);
                                            const yearNum2 = parseInt(parts2[3], 10);
                                            if (monthIndex2 >= 0 && !isNaN(dayNum2) && !isNaN(yearNum2)) {
                                                const dt = new Date(Date.UTC(yearNum2, monthIndex2, dayNum2));
                                                return days[dt.getUTCDay()];
                                            }
                                        }
                                        const dtFallback = new Date(label);
                                        return days[dtFallback.getDay()];
                                    } catch (e) {
                                        return '';
                                    }
                                },
                                font: { size: 9 },
                            },
                            grid: {
                                display: false,
                            },
                        },
                        y: {
                            stacked: true,
                            title: {
                                display: true,
                                text: 'Hours',
                            },
                            grid: {
                                display: false,
                            },
                        },
                    },
                },
            });
            // Attach a reference so tick callback can access component if needed
            // (Chart internals don't expose component; this is a small helper reference)
            this.attendanceChart._component = this;
        }
    }
}