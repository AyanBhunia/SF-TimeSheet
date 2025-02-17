// chartOne.js
import { LightningElement, api, track, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import ChartJS from '@salesforce/resourceUrl/jsChart';
import { getChartData } from 'c/dashboardSharedData';
import USER_ID from '@salesforce/user/Id';

// LMS imports
import { subscribe, MessageContext } from 'lightning/messageService';
import SELECTED_USER_CHANNEL from '@salesforce/messageChannel/SelectedUserChannel__c';

export default class ChartOne extends LightningElement {
    @track chartData;

    attendanceChart;
    isChartJsInitialized = false;
    selectedLevel = 'year';

    goals = { year: 1920, month: 160, week: 40, day: 8 };

    // State variables to keep track of current indices
    currentYearIndex = 0;
    currentMonthIndex = 0;
    currentWeekIndex = 0;
    currentDayIndex = 0;

    // LMS
    @wire(MessageContext)
    messageContext;

    subscription = null;
    selectedUserId = USER_ID; // Set to current user by default

    eventListenersAttached = false;

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

        // Reset indices
        this.currentYearIndex = 0;
        this.currentMonthIndex = 0;
        this.currentWeekIndex = 0;
        this.currentDayIndex = 0;
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
                this.initializeChart();
            })
            .catch(error => {
                console.error('Error loading ChartJS', error);
            });
    }

    initializeChart() {
        console.log("start 1",this.selectedUserId);
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

    showChart() {
        const canvas = this.template.querySelector('canvas');
        const ctx = canvas.getContext('2d');

        if(this.chartData == 0) {
            this.template.querySelector('.slds-m-around_x-small').style.display = 'none';
            return;
        }
        this.template.querySelector('.slds-m-around_x-small').style.removeProperty('display');

        // If event listeners are already attached, no need to attach them again
        if (!this.eventListenersAttached) {
            // Attach event listeners
            const levelSelector = this.template.querySelector('[data-id="levelSelector"]');
            const prevButton = this.template.querySelector('[data-id="prevButton"]');
            const nextButton = this.template.querySelector('[data-id="nextButton"]');

            levelSelector.addEventListener('click', this.handleLevelSelection.bind(this));
            prevButton.addEventListener('click', this.handlePrevClick.bind(this));
            nextButton.addEventListener('click', this.handleNextClick.bind(this));

            this.eventListenersAttached = true;
        }

        // Render the chart with the latest data by default
        this.renderChart(this.selectedLevel, ctx);
    }

    handleLevelSelection(event) {
        if (event.target.tagName === 'BUTTON') {
            this.selectedLevel = event.target.getAttribute('data-level');

            // Reset indices for the selected level to point to the latest data
            if (this.selectedLevel === 'year') this.currentYearIndex = 0;
            else if (this.selectedLevel === 'month') this.currentMonthIndex = 0;
            else if (this.selectedLevel === 'week') this.currentWeekIndex = 0;
            else if (this.selectedLevel === 'day') this.currentDayIndex = 0;

            const ctx = this.template.querySelector('canvas').getContext('2d');
            this.renderChart(this.selectedLevel, ctx);
        }
    }

    handlePrevClick() {
        this.navigateData(-1);
    }

    handleNextClick() {
        this.navigateData(1);
    }

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

    clampIndex(index, length) {
        if (index < 0) {
            return length - 1;
        } else if (index >= length) {
            return 0;
        } else {
            return index;
        }
    }

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
                    title: (data) => `Day: ${data.day}`,
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

        const colors = ['#228B22', '#32CD32', '#00FF00', '#7CFC00', '#7FFF00', '#ADFF2F', '#98FB98', '#90EE90'];

        const bg = colors.slice(0, pie_dataValues_2.length - 1).concat('#F44336');

        if (!pie_dataValues_1.length || !pie_dataValues_2.length) {
            // Handle the case when there's no data
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
                                    // Get the default label list
                                    const original = Chart.overrides.pie.plugins.legend.labels.generateLabels;
                                    const labelsOriginal = original.call(this, chart);

                                    // Build an array of colors used in the datasets of the chart
                                    let datasetColors = chart.data.datasets.map(function (e) {
                                        return e.backgroundColor;
                                    });
                                    datasetColors = datasetColors.flat();

                                    // Modify the color and hide state of each label
                                    labelsOriginal.forEach((label) => {
                                        // This converts the label index into the corresponding dataset index
                                        label.datasetIndex = label.index < 2 ? 0 : 1;

                                        // The hidden state must match the dataset's hidden state
                                        label.hidden = !chart.isDatasetVisible(label.datasetIndex);

                                        // Change the color to match the dataset
                                        label.fillStyle = datasetColors[label.index];
                                    });

                                    return labelsOriginal;
                                },
                            },
                            onClick: function (mouseEvent, legendItem, legend) {
                                // Toggle the visibility of the dataset
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