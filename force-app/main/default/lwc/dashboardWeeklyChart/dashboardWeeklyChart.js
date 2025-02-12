// chartTwo.js
import { LightningElement, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import ChartJS from '@salesforce/resourceUrl/jsChart';
import { getChartData } from 'c/dashboardSharedData';
import userId from '@salesforce/user/Id';

export default class ChartTwo extends LightningElement { 
    @track chartData;

    attendanceChart;
    isChartJsInitialized = false;
    currentWeekIndex = 0; // Initialize to the latest week

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
        if (userId) {
            getChartData(userId)
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

        // Attach event listeners
        const prevButton = this.template.querySelector('[data-id="prevButton"]');
        const nextButton = this.template.querySelector('[data-id="nextButton"]');

        prevButton.addEventListener('click', this.handlePrevClick.bind(this));
        nextButton.addEventListener('click', this.handleNextClick.bind(this));

        // Render the chart with the latest data by default
        this.renderChart(ctx);
    }

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

    clampIndex(index, length) {
        if (index < 0) {
            return length - 1;
        } else if (index >= length) {
            return 0;
        } else {
            return index;
        }
    }

    prepareChartData() {
        const { weekItems, getStartAndEndDate } = this.chartData;

        if (!weekItems || weekItems.length === 0) {
            return { datasets: [], labels: [], title: 'No Data' };
        }

        let weekString = getStartAndEndDate(weekItems[this.currentWeekIndex].week);
        const startDate = new Date(weekString.split(' - ')[0]);
        const endDate = new Date(weekString.split(' - ')[1]);

        const title = `Week: ${weekString}`;

        let barDataProjects = new Map();
        let barDataAbsence = [];
        let barDataAttendance = [];
        let barDataDurations = [];
        let barLabels = [];
        let barTarget = [8, 8, 8, 8, 8, 8, 8];

        let dayData = [];

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

        for (let d = new Date(startDate); d <= endDate; d.setDate(d.getDate() + 1)) {
            let dayString = d.toDateString();
            barLabels.push(dayString);

            // Put data for each project in the barDataProjects
            barDataProjects.forEach((value, key) => {
                if (dayData[dayString] && dayData[dayString].projects.has(key)) {
                    barDataProjects.get(key).push(dayData[dayString].projects.get(key));
                } else {
                    barDataProjects.get(key).push(0);
                }
            });

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

    renderChart(ctx) {
        // Colors array for more flexibility
        const colors = ['#228B22', '#32CD32', '#00FF00', '#7CFC00', '#7FFF00', '#ADFF2F', '#98FB98', '#90EE90'];

        const borderColors = ['#2E8B2E', '#3CBF3C', '#00CC00', '#72D700', '#73D700', '#9BDB2F', '#8EE48E', '#7BDEA7'];

        const {
            barDataDurations,
            barDataProjects,
            barDataAttendance,
            barDataAbsence,
            barTarget,
            barLabels,
            title
        } = this.prepareChartData();

        const projectDatasets = [];
        let colorIndex = 1; // Start after attendance and absence colors

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

        const datasets = [
            {
                label: 'Target',
                data: barTarget,
                backgroundColor: '#808080',
                borderColor: '#808080',
                type: 'line',
                order: 0,
            },
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

        if (this.attendanceChart) {
            // Update existing chart
            this.attendanceChart.data.labels = barLabels;
            this.attendanceChart.data.datasets = datasets;
            this.attendanceChart.options.plugins.title.text = title;
            this.attendanceChart.update();
        } else {
            // Create new chart
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
                                generateLabels: function (chart) {
                                    const original = Chart.defaults.plugins.legend.labels.generateLabels(chart);
                                    const customLabels = [];

                                    // Define the first four individual legend items: Target, Duration, Attendance, Absence
                                    const individualLabels = ['Target', 'Duration', 'Attendance', 'Absence'];

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

                                    // Add the 'Projects' legend item
                                    const projectsDatasets = chart.data.datasets.slice(4);
                                    const projectsHidden = projectsDatasets.every(ds => {
                                        const idx = chart.data.datasets.indexOf(ds);
                                        return chart.getDatasetMeta(idx).hidden;
                                    });

                                    // Determine the collective visibility
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
                            onClick: function (e, legendItem, legend) {
                                const chart = legend.chart;
                                const datasets = chart.data.datasets;
                                const clickedText = legendItem.text;
                                const isHidden = legendItem.hidden;

                                switch (clickedText) {
                                    case 'Target':
                                        // Toggle visibility of Target only
                                        const targetIndex = datasets.findIndex(ds => ds.label === 'Target');
                                        if (targetIndex !== -1) {
                                            const meta = chart.getDatasetMeta(targetIndex);
                                            meta.hidden = !meta.hidden;
                                            chart.update();
                                        }
                                        break;

                                    case 'Duration':
                                        if (isHidden) {
                                            // Show Duration, hide Attendance, Absence, Projects
                                            datasets.forEach((ds, idx) => {
                                                if (ds.label === 'Duration') {
                                                    chart.getDatasetMeta(idx).hidden = false;
                                                } else if (ds.label === 'Attendance' || ds.label === 'Absence') {
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                } else if (idx >= 4) { // Projects datasets
                                                    chart.getDatasetMeta(idx).hidden = true;
                                                }
                                            });
                                        } else {
                                            // Hide Duration, show Attendance and Absence, hide Projects
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
                                        if (isHidden) {
                                            // Show Attendance and Absence, hide Duration and Projects
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
                                            // Hide Attendance and Absence, show Duration, hide Projects
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
                                        if (isHidden) {
                                            // Show Projects and Absence, hide Duration and Attendance
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
                                            // Hide Projects and Absence, show Duration and Attendance
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