global class PostInstallScript implements System.InstallHandler {
    global void onInstall(System.InstallContext context) {
        // 1. Email to test@gmail.com
        sendInstallNotificationEmail(context);
        
        // 2. Promotional email to the current user
        sendPromotionalEmail(context);

        // 3. Update old Employee records to save Employment Type as 'Full Time'
        if (context.isUpgrade()) {
            updateEmployeeRecords();
        }
    }

    private static Id orgWideEmailAddressId;

    private static Id getOrgWideEmailAddressId() {
        if (orgWideEmailAddressId == null) {
            try {
                List<OrgWideEmailAddress> oweaList = [
                        SELECT Id 
                        FROM OrgWideEmailAddress 
                        ORDER BY CreatedDate ASC 
                        LIMIT 1 
                    ];
                if (!oweaList.isEmpty()) {
                    orgWideEmailAddressId = oweaList[0].Id;
                }
            } catch (Exception e) {
                System.debug('OWEA lookup failed: ' + e.getMessage());
            }
        }
        return orgWideEmailAddressId;
    }

    private static void tryApplyOrgWideAddress(Messaging.SingleEmailMessage mail) {
        try {
            Id oweaIdLocal = getOrgWideEmailAddressId();
            if (oweaIdLocal != null) {
                mail.setOrgWideEmailAddressId(oweaIdLocal);
            }
        } catch (Exception e) {
            System.debug('OWEA apply failed: ' + e.getMessage());
        }
    }

    private static void sendInstallNotificationEmail(System.InstallContext context) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        String[] toAddresses = new String[]{'srini.chappidi@digitalbiz.tech'};
        mail.setToAddresses(toAddresses);
        
        mail.setSubject('New Package Installation/Upgrade');
        
        User currentUser = [
                SELECT Name, Email 
                FROM User 
                WHERE Id = :context.installerId() 
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        Organization org = [
                SELECT Name, Id 
                FROM Organization 
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        
        String installType = context.isUpgrade() ? 'Upgrade' : 'Installation';
        String body = 'A new ' + installType + ' has occurred.\n\n' +
                      'User Details:\n' +
                      'Name: ' + currentUser.Name + '\n' +
                      'Email: ' + currentUser.Email + '\n\n' +
                      'Org Details:\n' +
                      'Company: ' + org.Name + '\n' +
                      'Org ID: ' + org.Id + '\n\n' +
                      'Package Details:\n' +
                      'Type: ' + installType;
                      
        mail.setPlainTextBody(body);
        tryApplyOrgWideAddress(mail);
        try {
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
        } catch (Exception e) {
            System.debug('sendInstallNotificationEmail (install path) failed to send: ' + e.getMessage());
        }
    }

    private static void sendPromotionalEmail(System.InstallContext context) {
        User currentUser = [
                SELECT Email 
                FROM User 
                WHERE Id = :context.installerId() 
                WITH SECURITY_ENFORCED
                LIMIT 1 
            ];

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        String[] toAddresses = new String[]{currentUser.Email};
        mail.setToAddresses(toAddresses);
        
        mail.setSubject('Welcome to Simple Timesheet! Time tracking just got easier');

        String body = 'Hi there,\n\n' +
                  'Thank you for installing Simple Timesheet. Your workspace is ready and your team can now enter their hours from any device.\n\n' +
                  'To get started, please check the documentations:\n' +
                  'Installation Guide: https://docs.google.com/document/d/1z69SRqGj4dCdIHVD0gcvybLHx3uVWflJp3_m82CkbGs/edit?usp=sharing\n' +
                  'Usage Guide: https://docs.google.com/document/d/16vZrD7bXlWISK9W4C5gFQJtLQh4gXN-25mGs9l3rBKg/edit?usp=sharing\n\n' +
                  'If you have any questions or custom requirments, reply to below email and we will be happy to help.\n\n' +
                  'Glad to have you with us!\n\n' +
                  'Best regards,\n' +
                  'Digital Biz Tech\n'+
                  'srini.chappidi@digitalbiz.tech';

        mail.setPlainTextBody(body);
        tryApplyOrgWideAddress(mail);
        try {
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
        } catch (Exception e) {
            System.debug('sendPromotionalEmail (install path) failed to send: ' + e.getMessage());
        }
    }

    private static void updateEmployeeRecords() {
        List<Employee__c> employeesToUpdate = [
                SELECT Id, Employment_Type__c, Total_Accrued_Hours__c, Total_Absence_Hours__c 
                FROM Employee__c 
                WHERE Employment_Type__c = '' 
                OR Total_Accrued_Hours__c = NULL 
                OR Total_Absence_Hours__c = NULL 
                WITH SECURITY_ENFORCED
            ];
        
        for (Employee__c emp : employeesToUpdate) {
            if (String.isBlank(emp.Employment_Type__c)) {
                emp.Employment_Type__c = 'Full Time';
            }
            if (emp.Total_Accrued_Hours__c == null) {
                emp.Total_Accrued_Hours__c = 0;
            }
            if (emp.Total_Absence_Hours__c == null) {
                emp.Total_Absence_Hours__c = 0;
            }
        }

        if (!employeesToUpdate.isEmpty()) {
            try {
                update employeesToUpdate;
            } catch (Exception e) {
                System.debug('updateEmployeeRecords failed: ' + e.getMessage());
            }
        }
    }
}