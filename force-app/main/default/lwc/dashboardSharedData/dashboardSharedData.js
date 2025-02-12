import getDashboardTimesheetLineItemsDetails from "@salesforce/apex/GetDashboardTimesheetLineItems.getDashboardTimesheetLineItemsDetails";

let cachedData = {};  // Stores processed data per recordId
let fetchPromises = {};  // Stores ongoing fetch promises per recordId

export async function getChartData(recordId) {
    // console.log("enter getChartData dashboard", recordId);
    console.log("enter");

    if (cachedData[recordId]) {
        return cachedData[recordId];  // Return cached processed data
    }

    if (!fetchPromises[recordId]) {
        fetchPromises[recordId] = getDashboardTimesheetLineItemsDetails({userID: recordId })
            .then((data) => {

                // console.log("shared data data", JSON.stringify(data));
                // Process the fetched data into maps using the helper function
                const processedData = processData(data);

                // console.log("processedData", processedData);
                console.log("exit 1");

                // Store processed maps in cache
                cachedData[recordId] = processedData;
                return processedData;
            })
            .catch((error) => {
                fetchPromises[recordId] = null;  // Reset on failure
                throw error;
            });
    }

    console.log("exit 2");

    return fetchPromises[recordId];  // Return the promise to avoid duplicate calls
}

//function to proccess SOQL result
function processData(abc) {
    const years_months = new Map();
    const weeks = new Map();

    // Helper function to get or initialize a Map entry
    const getOrSet = (map, key, defaultValue) => {
        if (!map.has(key)) {
        map.set(key, defaultValue);
        }
        return map.get(key);
    };

    const millisecondsInWeek = 604800000; // Number of milliseconds in one week
    
    // Get the earliest date in the dataset
    const minDate = new Date(abc[abc.length - 1].dbt__Date__c);
    const startOfFirstWeek = getMonday(minDate);  

    function getMonday(date) {  
    date.setDate(date.getDate() - (date.getDay() || 7) + 1);  
    return date.setHours(0, 0, 0, 0), date;  
    }

    // Function to get the start and end date from a continuous week number and return as formatted string
    function getStartAndEndDate(weekNumber) {
    const startDate = new Date(startOfFirstWeek.getTime() + (weekNumber - 1) * millisecondsInWeek);
    const endDate = new Date(startDate.getTime() + 518400000); // 6 days in ms

    // Ensure time is set to midnight for consistency
    startDate.setHours(0, 0, 0, 0);
    endDate.setHours(23, 59, 59, 999); // End of the day

    return `${startDate.toDateString()} - ${endDate.toDateString()}`;
    }

    abc.forEach(({ dbt__Type__c, dbt__Date__c, Name, duration }) => {
    const date = new Date(dbt__Date__c);
    const year = date.getFullYear();
    const month = date.toLocaleString('default', { month: 'short' }).toLowerCase();
    const day = date.toDateString();
    const week = Math.floor((getMonday(date) - startOfFirstWeek) / millisecondsInWeek) + 1;

    // Get or initialize yearData
    const yearData = getOrSet(years_months, year, {
        months: new Map(),
        projects: new Map(),
        duration: 0,
        attendance: 0,
        absence: 0,
    });

    // Get or initialize monthData
    const monthData = getOrSet(yearData.months, month, {
        projects: new Map(),
        duration: 0,
        attendance: 0,
        absence: 0,
    });

    // Get or initialize weekData
    const weekData = getOrSet(weeks, week, {
        dates: new Map(),
        projects: new Map(),
        duration: 0,
        attendance: 0,
        absence: 0,
    });

    // Get or initialize dayData
    const dayData = getOrSet(weekData.dates, day, {
        projects: new Map(),
        duration: 0,
        attendance: 0,
        absence: 0,
    });

    // Update total duration
    dayData.duration += duration;
    weekData.duration += duration;
    monthData.duration += duration;
    yearData.duration += duration;

    if (dbt__Type__c === "Attendance") {
        // Update total attendance duration
        dayData.attendance += duration;
        weekData.attendance += duration;
        monthData.attendance += duration;
        yearData.attendance += duration;

        // Increment individual Name's duration in the Map
        dayData.projects.set(Name, (dayData.projects.get(Name) || 0) + duration);
        weekData.projects.set(Name, (weekData.projects.get(Name) || 0) + duration);
        monthData.projects.set(Name, (monthData.projects.get(Name) || 0) + duration);
        yearData.projects.set(Name, (yearData.projects.get(Name) || 0) + duration);
    } else if (dbt__Type__c === "Absence") {
        // Update total absence duration
        dayData.absence += duration;
        weekData.absence += duration;
        monthData.absence += duration;
        yearData.absence += duration;
    }
    });


    // console.log(years_months);

    const yearItems = [];
    const monthItems = [];
    const weekItems = [];
    const dayItems = [];

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

    // console.log("yearItems",yearItems);
    // console.log("monthItems",monthItems);
    // console.log("weekItems",weekItems);
    // console.log("dayItems",dayItems);

    return { yearItems, monthItems, weekItems, dayItems, getStartAndEndDate};
}