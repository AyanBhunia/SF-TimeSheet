/**
 * @file dashboardSharedData.js
 * @description Service for handling dashboard timesheet data processing and caching
 */

import getDashboardTimesheetLineItemsDetails from "@salesforce/apex/GetDashboardTimesheetLineItems.getDashboardTimesheetLineItemsDetails";

// Cache storage for optimizing repeated requests
let cachedData = {};  // Stores processed data per user_id
let fetchPromises = {};  // Stores ongoing fetch promises per user_id

/**
 * @description Fetches and processes chart data for a given user ID
 * @param {String} user_id - The user ID to fetch data for
 * @returns {Promise<Object|Number>} Processed chart data or 0 if no data
 */
export async function getChartData(user_id) {

    // Return cached data if available
    if (cachedData[user_id]) {
        return cachedData[user_id];
    }

    // Prevent duplicate API calls for the same user_id
    if (!fetchPromises[user_id]) {
        fetchPromises[user_id] = getDashboardTimesheetLineItemsDetails({userID: user_id })
            .then((data) => {

                let processedData;

                // Handle empty data case
                if(data.length==0) {
                    processedData = 0;
                } else {
                    processedData = processData(data);
                }

                // Cache the processed data
                cachedData[user_id] = processedData;
                return processedData;
            })
            .catch((error) => {
                // Clear failed promise from cache
                fetchPromises[user_id] = null;
                throw error;
            });
    }

    return fetchPromises[user_id];
}

/**
 * @description Processes raw timesheet data into structured format
 * @param {Array} abc - Raw timesheet data array
 * @returns {Object} Processed data with year, month, week, and day aggregations
 */
function processData(abc) {
    // Main data storage structures
    const years_months = new Map();
    const weeks = new Map();

    /**
     * @description Helper function to safely get or initialize Map entries
     * @param {Map} map - Target map
     * @param {*} key - Map key
     * @param {*} defaultValue - Default value if key doesn't exist
     */
    const getOrSet = (map, key, defaultValue) => {
        if (!map.has(key)) {
        map.set(key, defaultValue);
        }
        return map.get(key);
    };

    // Time constants
    const millisecondsInWeek = 604800000; // 7 days in milliseconds
    const millisecondsInDay = 86400000;

    // Helper: parse incoming Salesforce date/datetime to a Date anchored at UTC midnight
    function parseToUTCDate(input) {
        // If input is already a Date object, convert to UTC midnight
        if (input instanceof Date) {
            return new Date(Date.UTC(input.getUTCFullYear(), input.getUTCMonth(), input.getUTCDate()));
        }

        // If input is like "YYYY-MM-DD" (Salesforce Date), append Z to treat as UTC date
        // If input includes time or timezone, create Date and then normalize to UTC midnight
        if (typeof input === 'string') {
            // If it's exactly YYYY-MM-DD (no "T"), handle as date-only
            const dateOnlyMatch = /^\d{4}-\d{2}-\d{2}$/.test(input);
            if (dateOnlyMatch) {
                const [y, m, d] = input.split('-').map(Number);
                return new Date(Date.UTC(y, m - 1, d));
            } else {
                // Has time component / timezone; create Date and then normalize to UTC midnight
                const dt = new Date(input);
                return new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate()));
            }
        }

        // Fallback
        const dt = new Date(input);
        return new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate()));
    }

    // Helper: get Monday (start of week) in UTC for a given date (returns a Date at UTC midnight)
    function getMondayUTC(date) {
        const dt = parseToUTCDate(date); // dt is UTC midnight of that date
        const day = dt.getUTCDay(); // 0 (Sun) - 6 (Sat)
        const daysToSubtract = (day + 6) % 7; // converts so Monday -> 0, Sunday -> 6
        const mondayTime = dt.getTime() - (daysToSubtract * millisecondsInDay);
        return new Date(Date.UTC(new Date(mondayTime).getUTCFullYear(), new Date(mondayTime).getUTCMonth(), new Date(mondayTime).getUTCDate()));
    }

    // Helper: format a Date (UTC) similarly to Date.prototype.toDateString() but using UTC values
    const shortDayNames = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    const shortMonthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    function formatDateStringUTC(date) {
        const d = parseToUTCDate(date);
        const dayName = shortDayNames[d.getUTCDay()];
        const monthName = shortMonthNames[d.getUTCMonth()];
        const dayNum = d.getUTCDate();
        const year = d.getUTCFullYear();
        // zero-pad day number to two digits when < 10
        const pad = (n) => (n < 10 ? '0' + n : String(n));
        return `${dayName} ${monthName} ${pad(dayNum)} ${year}`;
    }

    // Helper: get short month lowercased (consistent with previous behavior)
    function getMonthShortLowerUTC(date) {
        const d = parseToUTCDate(date);
        return shortMonthNames[d.getUTCMonth()].toLowerCase();
    }

    // Get reference date for week calculations (use last element like original code but normalize to UTC)
    const minDate = parseToUTCDate(abc[abc.length - 1].dbt__Date__c);
    const startOfFirstWeek = getMondayUTC(minDate);

    /**
     * @description Generates formatted date range string for a week
     * @param {Number} weekNumber - Week number
     * @returns {String} Formatted date range
     */
    function getStartAndEndDate(weekNumber) {
        const startDate = new Date(startOfFirstWeek.getTime() + (weekNumber - 1) * millisecondsInWeek);
        const endDate = new Date(startDate.getTime() + 6 * millisecondsInDay); // 6 days in ms

        // Use UTC-based formatting consistent with the rest
        return `${formatDateStringUTC(startDate)} - ${formatDateStringUTC(endDate)}`;
    }

    // Process each timesheet entry
    // A project the viewer cannot see has no name; show it as "Other projects" instead of "undefined".
    abc.forEach(({ dbt__Type__c, dbt__Date__c, Name = 'Other projects', duration }) => {
        // Parse and anchor date to UTC midnight to avoid local timezone shifts
        const dateUTC = parseToUTCDate(dbt__Date__c);

        // Extract date components using UTC methods
        const year = dateUTC.getUTCFullYear();
        const month = getMonthShortLowerUTC(dateUTC); // short month in lowercase
        const day = formatDateStringUTC(dateUTC); // formatted day string similar to toDateString but UTC-aware (day zero-padded)
        const week = Math.floor((getMondayUTC(dateUTC).getTime() - startOfFirstWeek.getTime()) / millisecondsInWeek) + 1;

        // Initialize or get year data
        const yearData = getOrSet(years_months, year, {
            months: new Map(),
            projects: new Map(),
            duration: 0,
            attendance: 0,
            absence: 0,
        });

        // Initialize or get month data
        const monthData = getOrSet(yearData.months, month, {
            projects: new Map(),
            duration: 0,
            attendance: 0,
            absence: 0,
        });

        // Initialize or get week data
        const weekData = getOrSet(weeks, week, {
            dates: new Map(),
            projects: new Map(),
            duration: 0,
            attendance: 0,
            absence: 0,
        });

        // Initialize or get day data
        const dayData = getOrSet(weekData.dates, day, {
            projects: new Map(),
            duration: 0,
            attendance: 0,
            absence: 0,
        });

        // Update duration totals
        dayData.duration += duration;
        weekData.duration += duration;
        monthData.duration += duration;
        yearData.duration += duration;

        // Process attendance entries
        if (dbt__Type__c === "Attendance") {
            // Update attendance totals
            dayData.attendance += duration;
            weekData.attendance += duration;
            monthData.attendance += duration;
            yearData.attendance += duration;

            // Update project-specific durations
            dayData.projects.set(Name, (dayData.projects.get(Name) || 0) + duration);
            weekData.projects.set(Name, (weekData.projects.get(Name) || 0) + duration);
            monthData.projects.set(Name, (monthData.projects.get(Name) || 0) + duration);
            yearData.projects.set(Name, (yearData.projects.get(Name) || 0) + duration);
        } 
        // Process absence entries
        else if (dbt__Type__c === "Absence") {
            dayData.absence += duration;
            weekData.absence += duration;
            monthData.absence += duration;
            yearData.absence += duration;
        }
    });

    // Prepare result arrays
    const yearItems = [];
    const monthItems = [];
    const weekItems = [];
    const dayItems = [];

    // Format year and month data
    years_months.forEach((yearData, yearKey) => {
        yearItems.push({
            year: yearKey,
            projects: yearData.projects,
            attendance: yearData.attendance,
            absence: yearData.absence,
            duration: yearData.duration
        });

        yearData.months.forEach((monthData, monthKey) => {
            monthItems.push({
                year: yearKey,
                month: monthKey,
                projects: monthData.projects,
                attendance: monthData.attendance,
                absence: monthData.absence,
                duration: monthData.duration
            });
        });
    });

    // Format week and day data
    weeks.forEach((weekData, weekKey) => {
        const week = {
            week: weekKey,
            projects: weekData.projects,
            attendance: weekData.attendance,
            absence: weekData.absence,
            duration: weekData.duration,
            dates: []
        };
        
        weekData.dates.forEach((dayData, dayKey) => {
            dayItems.push({
                week: weekKey,
                day: dayKey,
                projects: dayData.projects,
                attendance: dayData.attendance,
                absence: dayData.absence,
                duration: dayData.duration
            });
            week.dates.push(dayItems[dayItems.length-1]);
        });

        weekItems.push(week);
    });

    // Return processed data structure
    return { yearItems, monthItems, weekItems, dayItems, getStartAndEndDate};
}