/**
 * @file dashboardPieChart.js
 * @description LWC for displaying timesheet data in pie chart format with time period navigation
 */

import { LightningElement, api, track, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import ChartJS from '@salesforce/resourceUrl/jsChart';
import { getChartData } from 'c/dashboardSharedData';
import USER_ID from '@salesforce/user/Id';

// LMS imports for handling user selection
import { subscribe, MessageContext } from 'lightning/messageService';
import SELECTED_USER_CHANNEL from '@salesforce/messageChannel/UserChannel__c';

export default class dashboardPieChart extends LightningElement {
    @track chartData;

    // Chart configuration properties
    attendanceChart;
    isChartJsInitialized = false;
    selectedLevel = 'year';

    // Time period goals in hours
    goals = { year: 1920, month: 160, week: 40, day: 8 };

    // Navigation state indices
    currentYearIndex = 0;
    currentMonthIndex = 0;
    currentWeekIndex = 0;
    currentDayIndex = 0;

    // LMS configuration
    @wire(MessageContext)
    messageContext;

    subscription = null;
    selectedUserId = USER_ID; // Default to current user

    // Track event listener initialization
    eventListenersAttached = false;

    /**
     * UTC helpers to avoid timezone shifts when parsing/formatting the day string.
     * - parseDayStringToUTC expects the same format used in dashboardSharedData: "Mon Jan 01 2024"
     * - formatUTCDateKey returns the same format (with zero-padded day) and is timezone-safe.
     */
    shortDayNames = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    shortMonthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    pad(n) { return n < 10 ? '0' + n : String(n); }

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
                // Construct Date at UTC midnight for that date (avoids local-timezone offset)
                return new Date(Date.UTC(yearNum, monthIndex, dayNum));
            }
        }
        // fallback - parse then normalize to UTC midnight
        const dt = new Date(str);
        return new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate()));
    }

    formatUTCDateKey(dateObj) {
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

        // Reset indices when user changes
        this.currentYearIndex = 0;
        this.currentMonthIndex = 0;
        this.currentWeekIndex = 0;
        this.currentDayIndex = 0;
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
            this.template.querySelector('.slds-m-around_x-small').style.display = 'none';
            return;
        }
        this.template.querySelector('.slds-m-around_x-small').style.removeProperty('display');

        // Attach event listeners if not already attached
        if (!this.eventListenersAttached) {
            const levelSelector = this.template.querySelector('[data-id="levelSelector"]');
            const prevButton = this.template.querySelector('[data-id="prevButton"]');
            const nextButton = this.template.querySelector('[data-id="nextButton"]');

            levelSelector.addEventListener('click', this.handleLevelSelection.bind(this));
            prevButton.addEventListener('click', this.handlePrevClick.bind(this));
            nextButton.addEventListener('click', this.handleNextClick.bind(this));

            this.eventListenersAttached = true;
        }

        this.renderChart(this.selectedLevel, ctx);
    }

    /**
     * @description Handles time period level selection
     */
    handleLevelSelection(event) {
        if (event.target.tagName === 'BUTTON') {
            this.selectedLevel = event.target.getAttribute('data-level');

            // Reset index for selected level
            if (this.selectedLevel === 'year') this.currentYearIndex = 0;
            else if (this.selectedLevel === 'month') this.currentMonthIndex = 0;
            else if (this.selectedLevel === 'week') this.currentWeekIndex = 0;
            else if (this.selectedLevel === 'day') this.currentDayIndex = 0;

            const ctx = this.template.querySelector('canvas').getContext('2d');
            this.renderChart(this.selectedLevel, ctx);
        }
    }

    /**
     * @description Navigation handlers
     */
    handlePrevClick() {
        this.navigateData(-1);
    }

    handleNextClick() {
        this.navigateData(1);
    }

    /**
     * @description Handles data navigation between time periods
     */
    navigateData(direction) {
        const { yearItems, monthItems, weekItems, dayItems } = this.chartData;

        if (this.selectedLevel === 'year') {
            this.currentYearIndex = this.clampIndex(this.currentYearIndex - direction, yearItems.length);
        } else if (this.selectedLevel === 'month') {
            this.currentMonthIndex = this.clampIndex(this.currentMonthIndex - direction, monthItems.length);
        } else if (this.selectedLevel === 'week') {
            this.currentWeekIndex = this.clampIndex(this.currentWeekIndex - direction, weekItems.length);
        } else if (this.selectedLevel === 'day') {
            this.currentDayIndex = this.clampIndex(this.currentDayIndex - direction, dayItems.length);
        }

        const ctx = this.template.querySelector('canvas').getContext('2d');
        this.renderChart(this.selectedLevel, ctx);
    }

    /**
     * @description Ensures index stays within bounds
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
     * @description Renders the pie chart with current data
     */
    renderChart(level, ctx) {
        const { yearItems, monthItems, weekItems, dayItems, getStartAndEndDate } = this.chartData;

        const prepareChartData = (level) => {
            const pie_labels = ['Duration', 'Remaining'];

            const levelMap = {
                year: {
                    items: yearItems,
                    currentIndex: this.currentYearIndex,
                    goal: this.goals.year,
                    title: (data) => `Year: ${data.year}`,
                },
                month: {
                    items: monthItems,
                    currentIndex: this.currentMonthIndex,
                    goal: this.goals.month,
                    title: (data) => `Month: ${data.month} ${data.year}`,
                },
                week: {
                    items: weekItems,
                    currentIndex: this.currentWeekIndex,
                    goal: this.goals.week,
                    title: (data) => `Week: ${getStartAndEndDate(data.week)}`,
                },
                day: {
                    items: dayItems,
                    currentIndex: this.currentDayIndex,
                    goal: this.goals.day,
                    // Use UTC-safe parsing/formatting to avoid timezone drift
                    title: (data) => {
                        const parsed = this.parseDayStringToUTC(data.day);
                        const formatted = this.formatUTCDateKey(parsed);
                        return `Day: ${formatted}`;
                    },
                },
            };

            const levelData = levelMap[level];
            if (!levelData || levelData.items.length === 0) {
                return { pie_dataValues_1: [], pie_dataValues_2: [], pie_labels: [], title: 'No Data' };
            }

            const data = levelData.items[levelData.currentIndex];
            const pie_dataValues_1 = [
                data.duration,
                Math.max(0, levelData.goal - data.duration),
            ];

            const pie_dataValues_2 = [...data.projects.values(), data.absence];
            pie_labels.push(...data.projects.keys(), 'Absence');

            const title = levelData.title(data);

            return { pie_dataValues_1, pie_dataValues_2, pie_labels, title };
        };

        const { pie_dataValues_1, pie_dataValues_2, pie_labels, title } = prepareChartData(level);

        // Chart colors configuration
        const colors = ['#228B22', '#32CD32', '#00FF00', '#7CFC00', '#7FFF00', '#ADFF2F', '#98FB98', '#90EE90'];
        const bg = colors.slice(0, pie_dataValues_2.length - 1).concat('#F44336');

        if (!pie_dataValues_1.length || !pie_dataValues_2.length) {
            return;
        } else if (this.attendanceChart) {
            // Update existing chart
            this.attendanceChart.data.labels = pie_labels;
            this.attendanceChart.data.datasets[0].data = pie_dataValues_1;
            this.attendanceChart.data.datasets[1].data = pie_dataValues_2;
            this.attendanceChart.data.datasets[1].backgroundColor = bg;
            this.attendanceChart.options.plugins.title.text = title;
            this.attendanceChart.update();
        } else {
            // Create new chart
            this.attendanceChart = new Chart(ctx, {
                type: 'pie',
                data: {
                    labels: pie_labels,
                    datasets: [
                        {
                            data: pie_dataValues_1,
                            backgroundColor: ['#4F6F52', '#d8dace'],
                        },
                        {
                            data: pie_dataValues_2,
                            backgroundColor: bg,
                        },
                    ],
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        title: {
                            display: true,
                            text: title,
                        },
                        legend: {
                            labels: {
                                generateLabels: function (chart) {
                                    const original = Chart.overrides.pie.plugins.legend.labels.generateLabels;
                                    const labelsOriginal = original.call(this, chart);

                                    let datasetColors = chart.data.datasets.map(function (e) {
                                        return e.backgroundColor;
                                    });
                                    datasetColors = datasetColors.flat();

                                    labelsOriginal.forEach((label) => {
                                        label.datasetIndex = label.index < 2 ? 0 : 1;
                                        label.hidden = !chart.isDatasetVisible(label.datasetIndex);
                                        label.fillStyle = datasetColors[label.index];
                                    });

                                    return labelsOriginal;
                                },
                            },
                            onClick: function (mouseEvent, legendItem, legend) {
                                legend.chart.getDatasetMeta(legendItem.datasetIndex).hidden = legend.chart.isDatasetVisible(legendItem.datasetIndex);
                                legend.chart.update();
                            },
                            onHover: function handleHover(evt, item, legend) {
                                if (item.datasetIndex == 1)
                                    legend.chart.data.datasets[1].backgroundColor.forEach((color, index, colors) => {
                                        colors[index] = index === item.index - item.datasetIndex * 2 || color.length === 9 ? color : color + '4D';
                                    });
                                legend.chart.update();
                            },
                            onLeave: function handleLeave(evt, item, legend) {
                                if (item.datasetIndex == 1)
                                    legend.chart.data.datasets[1].backgroundColor.forEach((color, index, colors) => {
                                        colors[index] = color.length === 9 ? color.slice(0, -2) : color;
                                    });
                                legend.chart.update();
                            },
                        },
                        tooltip: {
                            callbacks: {
                                title: function (context) {
                                    const labelIndex = context[0].datasetIndex * 2 + context[0].dataIndex;
                                    return context[0].chart.data.labels[labelIndex];
                                },
                            },
                        },
                    },
                },
            });
        }
    }
}