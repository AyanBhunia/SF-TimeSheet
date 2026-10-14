import sys

p = 'Timesheet/main/default/classes/TimesheetApprovalController.cls'

with open(p, 'r', encoding='utf8') as f:
    code = f.read()

target = """        String key = String.valueOf(ts.Id);
        TimesheetWrapper newWrapper = new TimesheetWrapper(
            key,
            String.valueOf(ts.Id),
            ts.Name,
            String.valueOf(ts.Employee__c),
            ts.Employee__r.Name,
            null,
            'All Projects',
            period,
            ts.Status__c,
            ts.Start_Date__c
        );
        newWrapper.isPartialAllowed = false;
        newWrapper.duration = (ts.Total_Hours__c != null) ? ts.Total_Hours__c : 0;
        wrapperMap.put(key, newWrapper);
        continue;"""

replacement = """        String key = String.valueOf(ts.Id);
        
        Set<String> projectNames = new Set<String>();
        Set<String> activityNames = new Set<String>();
        
        if (ts.Timesheets__r != null) {
            for (Timesheet_Line_Item__c line : ts.Timesheets__r) {
                String pName = '';
                Boolean isAbsence = (line.Type__c == 'Absence');
                
                if (isAbsence) {
                    pName = String.isNotBlank(line.Absence_Category__c) ? line.Absence_Category__c : 'Absence';
                } else if (line.Project__c != null && line.Project__r != null) {
                    pName = line.Project__r.Name;
                } else {
                    pName = String.isNotBlank(line.Type__c) ? line.Type__c : 'N/A';
                }
                
                if (String.isNotBlank(pName)) {
                    projectNames.add(pName);
                }
                
                String aName = '';
                if (isAbsence) {
                    aName = '-';
                } else if (String.isNotBlank(line.Activity__c)) {
                    aName = line.Activity__c;
                } else if (String.isNotBlank(line.Description__c)) {
                    aName = line.Description__c;
                } else if (String.isNotBlank(line.Type__c)) {
                    aName = line.Type__c;
                } else {
                    aName = '-';
                }
                
                if (String.isNotBlank(aName)) {
                    activityNames.add(aName);
                }
            }
        }
        
        List<String> projList = new List<String>(projectNames);
        List<String> actList = new List<String>(activityNames);
        String finalProjectName = projList.isEmpty() ? 'Timesheet' : String.join(projList, ', ');
        String finalActivityName = actList.isEmpty() ? ts.Name : String.join(actList, ', ');

        TimesheetWrapper newWrapper = new TimesheetWrapper(
            key,
            String.valueOf(ts.Id),
            ts.Name,
            String.valueOf(ts.Employee__c),
            ts.Employee__r.Name,
            null,
            finalProjectName,
            period,
            ts.Status__c,
            ts.Start_Date__c
        );
        newWrapper.activityName = finalActivityName;
        newWrapper.isPartialAllowed = false;
        newWrapper.duration = (ts.Total_Hours__c != null) ? ts.Total_Hours__c : 0;
        wrapperMap.put(key, newWrapper);
        continue;"""

target_crlf = target.replace('\n', '\r\n')
code = code.replace(target, replacement)
code = code.replace(target_crlf, replacement)

with open(p, 'w', encoding='utf8') as f:
    f.write(code)

print('done')
