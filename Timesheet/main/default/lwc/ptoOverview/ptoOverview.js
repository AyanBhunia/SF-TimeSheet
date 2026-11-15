import { LightningElement, api, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import ChartJS from '@salesforce/resourceUrl/jsChart';
import jsChartMatrix from '@salesforce/resourceUrl/jsChartMatrix';
import getOverview from '@salesforce/apex/PtoController.getOverview';
import getTeamYear from '@salesforce/apex/PtoController.getTeamYear';

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

export default class PtoOverview extends LightningElement {
    @track overview;
    @track teamYear;
    @track error;
    isLoading = false;

    _context;
    _employeeId;
    connected = false;

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

    get pendingCaption() {
        const n = this.overview?.pendingRequests || 0;
        return n ? `In ${n} request${n === 1 ? '' : 's'}` : 'Nothing waiting for approval';
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

    // Approved, Pending approval, or "N pending approval" when only some days of the next leave are approved.
    get nextLeaveStage() {
        const count = this.overview?.nextLeaveCount;
        if (!this.overview?.nextLeaveDate || !count) {
            return '';
        }
        const pending = this.overview?.nextLeavePendingCount || 0;
        if (!pending) {
            return 'Approved';
        }
        return pending >= count ? 'Pending approval' : `${pending} pending approval`;
    }

    get nextLeaveStageClass() {
        return this.nextLeaveStage === 'Approved' ? 'stage stage_approved' : 'stage stage_pending';
    }

    get hasCategoryData() {
        return (this.overview?.byCategory || []).length > 0;
    }

    get noCategoryData() {
        return !this.hasCategoryData;
    }

    get hasTeamData() {
        return (this.teamYear?.rows || []).length > 0;
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
        const count = (this.teamYear?.rows || []).length;
        const height = Math.max(160, count * 36 + 60);
        return `position: relative; height: ${height}px; width: 100%;`;
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
                await this.fetchTeamYear();
            }
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Error loading PTO overview.';
        } finally {
            this.isLoading = false;
            this.needsChartRender = true;
        }
    }

    async fetchTeamYear() {
        try {
            this.teamYear = await getTeamYear({ year: this.currentYear });
        } catch (e) {
            console.error('Error loading team leave:', e);
        }
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

        const rows = this.teamYear?.rows || [];
        const numEmployees = rows.length;
        if (numEmployees === 0) {
            return;
        }

        const format = (v) => this.formatNumber(v);
        const year = this.currentYear;
        const employeeLabels = rows.map((r) => `${r.name} · ${format(r.total)} h`);
        const matrixData = [];
        let maxHours = 0;
        rows.forEach((row, rowIndex) => {
            for (let day = 0; day < 7; day++) {
                const hours = Number((row.hours || [])[day]) || 0;
                maxHours = Math.max(maxHours, hours);
                matrixData.push({ x: day + 1, y: rowIndex + 1, v: hours, employeeName: row.name, day: DAYS[day] });
            }
        });

        // Five shades, scaled to the busiest cell in the chart.
        const FILL = ['#eef1f4', '#c3dcf2', '#7fb6e6', '#2f86d1', '#0b4f8f'];
        const BORDER = ['#dddbda', '#a9cbe9', '#5f9fd9', '#1f6fb5', '#083b6b'];
        const level = (v) => (!v || !maxHours ? 0 : Math.min(4, Math.ceil((v / maxHours) * 4)));
        const cellValue = (context) => {
            const item = context.dataset.data[context.dataIndex];
            return item ? Number(item.v) : 0;
        };

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
                    const point = chart.data.datasets[0].data[index];
                    if (!point || !point.v) {
                        return;
                    }
                    c.fillStyle = level(point.v) >= 3 ? '#ffffff' : '#181818';
                    const center = typeof element.getCenterPoint === 'function'
                        ? element.getCenterPoint()
                        : { x: element.x + (element.width || 0) / 2, y: element.y + (element.height || 0) / 2 };
                    if (center && !isNaN(center.x) && !isNaN(center.y)) {
                        c.fillText(format(point.v), center.x, center.y);
                    }
                });
                c.restore();
            }
        };

        const ChartLib = window.Chart;
        this.teamChart = new ChartLib(canvas.getContext('2d'), {
            type: 'matrix',
            data: {
                datasets: [
                    {
                        label: 'Team leave',
                        data: matrixData,
                        backgroundColor: (context) => FILL[level(cellValue(context))],
                        borderColor: (context) => BORDER[level(cellValue(context))],
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
                                return [item.employeeName, `${item.day}s in ${year}: ${format(item.v)} h approved`];
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
                            axis.ticks = DAYS.map((d, i) => ({ value: i + 1 }));
                        },
                        ticks: {
                            stepSize: 1,
                            autoSkip: false,
                            callback: (value) => DAYS[Math.round(value) - 1] || '',
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
                            axis.ticks = employeeLabels.map((n, i) => ({ value: i + 1 }));
                        },
                        ticks: {
                            stepSize: 1,
                            autoSkip: false,
                            callback: (value) => employeeLabels[Math.round(value) - 1] || '',
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
