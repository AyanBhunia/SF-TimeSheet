import { LightningElement, api, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import ChartJS from '@salesforce/resourceUrl/jsChart';
import jsChartMatrix from '@salesforce/resourceUrl/jsChartMatrix';
import getOverview from '@salesforce/apex/PtoController.getOverview';
import getTeamWeek from '@salesforce/apex/PtoController.getTeamWeek';

function getMonday(date) {
    const d = new Date(date);
    const day = d.getDay();
    const diff = (day + 6) % 7;
    d.setDate(d.getDate() - diff);
    return formatDate(d);
}

function formatDate(d) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

export default class PtoOverview extends LightningElement {
    @track overview;
    @track teamWeek;
    @track error;
    isLoading = false;

    _context;
    _employeeId;
    connected = false;

    currentWeekStart;
    scriptsLoaded = false;
    isChartJsInitialized = false;
    needsChartRender = false;

    categoryChart;
    teamChart;

    @api
    get context() {
        return this._context;
    }
    set context(value) {
        this._context = value;
        if (this.connected && !this.isLoading) {
            this.loadData();
        }
    }

    @api
    get employeeId() {
        return this._employeeId;
    }
    set employeeId(value) {
        const changed = this._employeeId !== value;
        this._employeeId = value;
        if (changed && this.connected && !this.isLoading) {
            this.loadData();
        }
    }

    @api
    async refresh() {
        await this.loadData();
    }

    connectedCallback() {
        this.connected = true;
        this.initWeekStart();
        this.loadData();
    }

    disconnectedCallback() {
        this.connected = false;
        if (this.categoryChart) {
            this.categoryChart.destroy();
            this.categoryChart = null;
        }
        if (this.teamChart) {
            this.teamChart.destroy();
            this.teamChart = null;
        }
    }

    renderedCallback() {
        if (!this.isChartJsInitialized) {
            this.isChartJsInitialized = true;
            loadScript(this, ChartJS)
                .then(() => loadScript(this, jsChartMatrix))
                .then(() => {
                    this.scriptsLoaded = true;
                    this.renderCharts();
                })
                .catch((error) => {
                    console.error('Error loading Chart.js or jsChartMatrix', error);
                });
            return;
        }

        if (this.scriptsLoaded && this.needsChartRender) {
            this.needsChartRender = false;
            this.renderCharts();
        }
    }

    initWeekStart() {
        if (!this.currentWeekStart) {
            const todayStr = this.context?.today;
            if (todayStr) {
                const [y, m, d] = todayStr.split('-').map(Number);
                this.currentWeekStart = getMonday(new Date(y, m - 1, d));
            } else {
                this.currentWeekStart = getMonday(new Date());
            }
        }
    }

    get targetEmployeeId() {
        return this.employeeId || this.context?.employee?.id;
    }

    get isManagerOrHr() {
        return !!(this.context?.isManager || this.context?.isHrAdmin || this.context?.canApprove);
    }

    get currentYear() {
        if (this.context?.today) {
            const parsed = parseInt(this.context.today.substring(0, 4), 10);
            if (!isNaN(parsed)) {
                return parsed;
            }
        }
        return new Date().getFullYear();
    }

    get availableDisplay() {
        const val = this.overview?.available;
        return val !== null && val !== undefined ? `${this.formatNumber(val)} h` : '0 h';
    }

    get takenDisplay() {
        const val = this.overview?.takenHours;
        return val !== null && val !== undefined ? `${this.formatNumber(val)} h` : '0 h';
    }

    get pendingDisplay() {
        const val = this.overview?.pendingHours;
        return val !== null && val !== undefined ? `${this.formatNumber(val)} h` : '0 h';
    }

    get nextLeaveDateDisplay() {
        return this.overview?.nextLeaveDate || 'None';
    }

    get nextLeaveCountDisplay() {
        const count = this.overview?.nextLeaveCount;
        if (!this.overview?.nextLeaveDate || !count) {
            return 'No upcoming leave';
        }
        return count === 1 ? '1 day' : `${count} days`;
    }

    get hasCategoryData() {
        return (this.overview?.byCategory || []).length > 0;
    }

    get noCategoryData() {
        return !this.hasCategoryData;
    }

    get hasTeamData() {
        return (this.teamWeek?.rows || []).length > 0;
    }

    get noTeamData() {
        return !this.hasTeamData;
    }

    get categoryChartContainerStyle() {
        const count = (this.overview?.byCategory || []).length;
        const height = Math.max(160, count * 36 + 60);
        return `position: relative; height: ${height}px; width: 100%;`;
    }

    get teamChartContainerStyle() {
        const count = (this.teamWeek?.rows || []).length;
        const height = Math.max(160, count * 36 + 60);
        return `position: relative; height: ${height}px; width: 100%;`;
    }

    get weekRangeLabel() {
        if (this.teamWeek?.days && this.teamWeek.days.length === 7) {
            return `${this.teamWeek.days[0]} to ${this.teamWeek.days[6]}`;
        }
        return this.currentWeekStart || '';
    }

    formatNumber(value) {
        if (value === null || value === undefined) {
            return '0';
        }
        const n = Number(value);
        return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/\.?0+$/, '');
    }

    async loadData() {
        this.isLoading = true;
        this.error = null;
        try {
            this.overview = await getOverview({
                employeeId: this.targetEmployeeId,
                year: this.currentYear
            });

            if (this.isManagerOrHr) {
                await this.fetchTeamWeek();
            }
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Error loading PTO overview.';
        } finally {
            this.isLoading = false;
            this.needsChartRender = true;
        }
    }

    async fetchTeamWeek() {
        try {
            this.teamWeek = await getTeamWeek({
                weekStart: this.currentWeekStart
            });
            if (this.teamWeek?.weekStart) {
                this.currentWeekStart = this.teamWeek.weekStart;
            }
        } catch (e) {
            console.error('Error loading team week:', e);
        }
    }

    async handlePrevWeek() {
        this.initWeekStart();
        const [y, m, d] = this.currentWeekStart.split('-').map(Number);
        const dt = new Date(y, m - 1, d);
        dt.setDate(dt.getDate() - 7);
        this.currentWeekStart = formatDate(dt);
        await this.fetchTeamWeek();
        this.needsChartRender = true;
    }

    async handleNextWeek() {
        this.initWeekStart();
        const [y, m, d] = this.currentWeekStart.split('-').map(Number);
        const dt = new Date(y, m - 1, d);
        dt.setDate(dt.getDate() + 7);
        this.currentWeekStart = formatDate(dt);
        await this.fetchTeamWeek();
        this.needsChartRender = true;
    }

    renderCharts() {
        if (!this.scriptsLoaded) {
            return;
        }
        this.renderCategoryChart();
        if (this.isManagerOrHr) {
            this.renderTeamChart();
        }
    }

    renderCategoryChart() {
        const canvas = this.template.querySelector('canvas[data-id="categoryChart"]');
        if (!canvas) {
            return;
        }

        if (this.categoryChart) {
            this.categoryChart.destroy();
            this.categoryChart = null;
        }

        const byCategory = this.overview?.byCategory || [];
        const labels = byCategory.map((item) => item.category);
        const approvedData = byCategory.map((item) => Number(item.approved) || 0);
        const submittedData = byCategory.map((item) => Number(item.submitted) || 0);

        const ChartLib = window.Chart;
        const ctx = canvas.getContext('2d');

        this.categoryChart = new ChartLib(ctx, {
            type: 'bar',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: 'Approved',
                        data: approvedData,
                        backgroundColor: '#2e844a',
                        borderColor: '#246b3b',
                        borderWidth: 1,
                        maxBarThickness: 28,
                        stack: 'hours'
                    },
                    {
                        label: 'Submitted',
                        data: submittedData,
                        backgroundColor: '#fe9339',
                        borderColor: '#dd7a01',
                        borderWidth: 1,
                        maxBarThickness: 28,
                        stack: 'hours'
                    }
                ]
            },
            options: {
                indexAxis: 'y',
                responsive: true,
                maintainAspectRatio: false,
                animation: { duration: 0 },
                plugins: {
                    legend: {
                        position: 'top',
                        align: 'end',
                        labels: {
                            boxWidth: 12,
                            font: { size: 11 }
                        }
                    },
                    tooltip: {
                        callbacks: {
                            label: (context) => {
                                const val = context.raw != null ? context.raw : 0;
                                return ` ${context.dataset.label}: ${val} h`;
                            }
                        }
                    }
                },
                scales: {
                    x: {
                        stacked: true,
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Hours'
                        },
                        ticks: {
                            precision: 0
                        },
                        grid: {
                            drawBorder: false
                        }
                    },
                    y: {
                        stacked: true,
                        ticks: {
                            font: { size: 11 }
                        },
                        grid: {
                            display: false,
                            drawBorder: false
                        }
                    }
                }
            }
        });
    }

    renderTeamChart() {
        const canvas = this.template.querySelector('canvas[data-id="teamChart"]');
        if (!canvas) {
            return;
        }

        if (this.teamChart) {
            this.teamChart.destroy();
            this.teamChart = null;
        }

        const rows = this.teamWeek?.rows || [];
        const numEmployees = rows.length;
        if (numEmployees === 0) {
            return;
        }

        const employeeNames = rows.map((r) => r.name);
        const matrixData = [];
        rows.forEach((row, rowIndex) => {
            const yVal = rowIndex + 1;
            const hoursList = row.hours || [0, 0, 0, 0, 0, 0, 0];
            for (let dayIndex = 0; dayIndex < 7; dayIndex++) {
                const xVal = dayIndex + 1;
                const hours = hoursList[dayIndex] != null ? Number(hoursList[dayIndex]) : 0;
                const dateStr = this.teamWeek?.days?.[dayIndex] || '';
                matrixData.push({
                    x: xVal,
                    y: yVal,
                    v: hours,
                    employeeName: row.name,
                    date: dateStr,
                    dayName: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dayIndex]
                });
            }
        });

        const drawHoursPlugin = {
            id: 'matrixHoursText',
            afterDatasetsDraw(chart) {
                const { ctx: c } = chart;
                const meta = chart.getDatasetMeta(0);
                if (!meta || !meta.data) {
                    return;
                }

                c.save();
                c.font = 'bold 11px sans-serif';
                c.textAlign = 'center';
                c.textBaseline = 'middle';

                meta.data.forEach((element, index) => {
                    const dataPoint = chart.data.datasets[0].data[index];
                    if (!dataPoint) {
                        return;
                    }
                    const hours = dataPoint.v;
                    if (!hours) {
                        return;
                    }
                    const text = String(hours);
                    c.fillStyle = Number(hours) > 4 ? '#ffffff' : '#181818';

                    let center;
                    if (typeof element.getCenterPoint === 'function') {
                        center = element.getCenterPoint();
                    } else {
                        const w = element.width || 0;
                        const h = element.height || 0;
                        center = { x: element.x + w / 2, y: element.y + h / 2 };
                    }
                    if (center && !isNaN(center.x) && !isNaN(center.y)) {
                        c.fillText(text, center.x, center.y);
                    }
                });

                c.restore();
            }
        };

        const ChartLib = window.Chart;
        const ctx = canvas.getContext('2d');

        this.teamChart = new ChartLib(ctx, {
            type: 'matrix',
            data: {
                datasets: [
                    {
                        label: 'Team Week',
                        data: matrixData,
                        backgroundColor: (context) => {
                            const item = context.dataset.data[context.dataIndex];
                            const val = item ? Number(item.v) : 0;
                            if (val === 0) return '#eef1f4';
                            if (val <= 2) return '#c3dcf2';
                            if (val <= 4) return '#7fb6e6';
                            if (val < 8) return '#2f86d1';
                            return '#0b4f8f';
                        },
                        borderColor: (context) => {
                            const item = context.dataset.data[context.dataIndex];
                            const val = item ? Number(item.v) : 0;
                            if (val === 0) return '#dddbda';
                            if (val <= 2) return '#a9cbe9';
                            if (val <= 4) return '#5f9fd9';
                            if (val < 8) return '#1f6fb5';
                            return '#083b6b';
                        },
                        borderWidth: 1,
                        width: (context) => {
                            const area = context.chart.chartArea;
                            return area ? Math.max(1, (area.right - area.left) / 7 - 2) : 20;
                        },
                        height: (context) => {
                            const area = context.chart.chartArea;
                            return area ? Math.max(1, (area.bottom - area.top) / numEmployees - 2) : 20;
                        }
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: { duration: 0 },
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        enabled: true,
                        displayColors: false,
                        callbacks: {
                            title: () => '',
                            label: (context) => {
                                const item = context.dataset.data[context.dataIndex];
                                return [
                                    `Employee: ${item.employeeName}`,
                                    `Day: ${item.dayName} (${item.date})`,
                                    `Hours: ${item.v}`
                                ];
                            }
                        }
                    }
                },
                scales: {
                    x: {
                        type: 'linear',
                        position: 'bottom',
                        offset: false,
                        min: 0.5,
                        max: 7.5,
                        afterBuildTicks: (axis) => {
                            axis.ticks = [1, 2, 3, 4, 5, 6, 7].map((v) => ({ value: v }));
                        },
                        ticks: {
                            stepSize: 1,
                            autoSkip: false,
                            callback: (value) => {
                                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                const idx = Math.round(value) - 1;
                                return days[idx] || '';
                            },
                            font: { size: 11, weight: 'bold' }
                        },
                        grid: { display: false, drawBorder: false }
                    },
                    y: {
                        type: 'linear',
                        position: 'left',
                        offset: false,
                        reverse: true,
                        min: 0.5,
                        max: numEmployees + 0.5,
                        afterBuildTicks: (axis) => {
                            axis.ticks = employeeNames.map((n, i) => ({ value: i + 1 }));
                        },
                        ticks: {
                            stepSize: 1,
                            autoSkip: false,
                            callback: (value) => {
                                const idx = Math.round(value) - 1;
                                return employeeNames[idx] || '';
                            },
                            font: { size: 11 }
                        },
                        grid: { display: false, drawBorder: false }
                    }
                }
            },
            plugins: [drawHoursPlugin]
        });
    }
}
