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
import SELECTED_USER_CHANNEL from '@salesforce/messageChannel/SelectedUserChannel__c';

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

        // Get week date range
        let weekString = getStartAndEndDate(weekItems[this.currentWeekIndex].week);
        const startDate = new Date(weekString.split(' - ')[0]);
        const endDate = new Date(weekString.split(' - ')[1]);

        const title = `Week: ${weekString}`;

        // Initialize data structures
        let barDataProjects = new Map();
        let barDataAbsence = [];
        let barDataAttendance = [];
        let barDataDurations = [];
        let barLabels = [];
        let barTarget = [8, 8, 8, 8, 8, 8, 8]; // Daily target hours

        let dayData = [];

        // Process week data
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

        // Generate daily data points
        for (let d = new Date(startDate); d <= endDate; d.setDate(d.getDate() + 1)) {
            let dayString = d.toDateString();
            barLabels.push(dayString);

            // Process project data
            barDataProjects.forEach((value, key) => {
                if (dayData[dayString] && dayData[dayString].projects.has(key)) {
                    barDataProjects.get(key).push(dayData[dayString].projects.get(key));
                } else {
                    barDataProjects.get(key).push(0);
                }
            });

            // Process attendance and absence data
            if (dayData[dayString]) {
                barDataAbsence.push(dayData[dayString].absence);
                barDataAttendance.push(dayData[dayString].attendance);
                barDataDurations.push(dayData[dayString].duration);
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
                                callback: function (value) {
                                    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
                                    const date = new Date(this.getLabelForValue(value));
                                    return days[date.getDay()];
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
        }
    }
}