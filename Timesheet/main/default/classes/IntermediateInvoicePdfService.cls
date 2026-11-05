public with sharing class IntermediateInvoicePdfService {

    public static void generatePdfs(List<Id> invoiceIds) {

        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return;
        }

        Map<Id, Intermediate_Invoice__c> invoiceMap =
            new Map<Id, Intermediate_Invoice__c>([
                SELECT Id, Name, Account__c,
                       Account__r.Name,
                       Invoice_Date__c,
                       Due_Date__c,
                       Billing_Period_Start__c,
                       Billing_Period_End__c,
                       Billing_Address__c,
                       Memo__c,
                       Total_Amount__c
                FROM Intermediate_Invoice__c
                WHERE Id IN :invoiceIds
            ]);

        Map<Id, List<Intermediate_Invoice_Line_Item__c>> lineMap =
            new Map<Id, List<Intermediate_Invoice_Line_Item__c>>();

        for (Id invoiceId : invoiceMap.keySet()) {
            lineMap.put(
                invoiceId,
                new List<Intermediate_Invoice_Line_Item__c>()
            );
        }

        for (Intermediate_Invoice_Line_Item__c line : [
            SELECT Id, Intermediate_Invoice__c,
                   Line_Number__c,
                   Project__r.Name,
                   Employee__r.Name,
                   Activity__c,
                   Description__c,
                   Quantity__c,
                   Unit_Price__c,
                   Service_Date__c
            FROM Intermediate_Invoice_Line_Item__c
            WHERE Intermediate_Invoice__c IN :invoiceMap.keySet()
            ORDER BY Line_Number__c ASC
        ]) {
            lineMap.get(line.Intermediate_Invoice__c).add(line);
        }

        List<ContentVersion> files = new List<ContentVersion>();

        for (Id invoiceId : invoiceMap.keySet()) {

            Intermediate_Invoice__c inv = invoiceMap.get(invoiceId);

            try {
                String html = buildInvoiceHtml(
                    inv,
                    lineMap.get(invoiceId)
                );

                Blob pdfBlob = Blob.toPDF(html);

                ContentVersion file = new ContentVersion();

                file.Title = 'Invoice-' + inv.Name;
                file.PathOnClient = 'Invoice-' + inv.Name + '.pdf';
                file.VersionData = pdfBlob;

                // Attach PDF to the Intermediate Invoice
                file.FirstPublishLocationId = inv.Id;

                files.add(file);

            } catch (Exception e) {

                System.debug(
                    LoggingLevel.ERROR,
                    'PDF generation failed for invoice ' +
                    invoiceId + ': ' + e.getMessage()
                );
            }
        }

        if (!files.isEmpty()) {

            Database.SaveResult[] results =
                Database.insert(files, false);

            for (Integer i = 0; i < results.size(); i++) {

                if (!results[i].isSuccess()) {

                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'PDF file save failed: ' +
                            err.getMessage()
                        );
                    }
                }
            }
        }
    }

    private static String buildInvoiceHtml(
        Intermediate_Invoice__c inv,
        List<Intermediate_Invoice_Line_Item__c> lines
    ) {

        String html = '';

        html += '<html><head><style>';

        html += '@page { size: A4; margin: 25px; }';

        html += 'body { font-family: Arial, sans-serif; ' +
                'font-size: 11px; color: #333; }';

        html += 'h1 { font-size: 28px; margin-bottom: 5px; }';

        html += '.header { border-bottom: 2px solid #333; ' +
                'padding-bottom: 15px; margin-bottom: 20px; }';

        html += '.details { width: 100%; margin-bottom: 20px; }';

        html += '.details td { padding: 5px; vertical-align: top; }';

        html += 'table.items { width: 100%; ' +
                'border-collapse: collapse; margin-top: 15px; }';

        html += '.items th, .items td { ' +
                'border: 1px solid #ccc; padding: 8px; }';

        html += '.items th { background: #eeeeee; }';

        html += '.right { text-align: right; }';

        html += '.total { text-align: right; ' +
                'font-size: 16px; font-weight: bold; margin-top: 20px; }';

        html += '</style></head><body>';

        // Invoice heading
        html += '<div class="header">';
        html += '<h1>INVOICE</h1>';
        html += '<b>Invoice Number: </b>' +
                escapeHtml(inv.Name);
        html += '</div>';

        // Invoice information
        html += '<table class="details">';

        html += '<tr><td><b>Bill To:</b><br/>' +
                escapeHtml(
                    inv.Account__r != null
                    ? inv.Account__r.Name : ''
                ) + '<br/>' +
                escapeHtml(inv.Billing_Address__c) +
                '</td>';

        html += '<td><b>Invoice Date:</b> ' +
                escapeHtml(String.valueOf(inv.Invoice_Date__c)) +
                '<br/>';

        html += '<b>Due Date:</b> ' +
                escapeHtml(String.valueOf(inv.Due_Date__c)) +
                '<br/>';

        html += '<b>Billing Period:</b> ' +
                escapeHtml(String.valueOf(inv.Billing_Period_Start__c)) +
                ' to ' +
                escapeHtml(String.valueOf(inv.Billing_Period_End__c)) +
                '</td></tr>';

        html += '</table>';

        // Line items
        html += '<table class="items">';

        html += '<thead><tr>';

        html += '<th>#</th>';
        html += '<th>Project</th>';
        html += '<th>Employee</th>';
        html += '<th>Activity</th>';
        html += '<th>Description</th>';
        html += '<th>Hours</th>';
        html += '<th>Rate</th>';
        html += '<th>Amount</th>';

        html += '</tr></thead><tbody>';

        Decimal calculatedTotal = 0;
        Integer index = 1;

        for (Intermediate_Invoice_Line_Item__c line : lines) {

            Decimal qty = line.Quantity__c == null
                ? 0 : line.Quantity__c;

            Decimal rate = line.Unit_Price__c == null
                ? 0 : line.Unit_Price__c;

            Decimal amount = (qty * rate).setScale(
                2,
                RoundingMode.HALF_UP
            );

            calculatedTotal += amount;

            html += '<tr>';

            html += '<td>' + index + '</td>';

            html += '<td>' +
                escapeHtml(
                    line.Project__r != null
                    ? line.Project__r.Name : ''
                ) + '</td>';

            html += '<td>' +
                escapeHtml(
                    line.Employee__r != null
                    ? line.Employee__r.Name : ''
                ) + '</td>';

            html += '<td>' +
                escapeHtml(line.Activity__c) + '</td>';

            html += '<td>' +
                escapeHtml(line.Description__c) + '</td>';

            html += '<td class="right">' +
                escapeHtml(String.valueOf(qty)) + '</td>';

            html += '<td class="right">' +
                escapeHtml(String.valueOf(rate)) + '</td>';

            html += '<td class="right">' +
                escapeHtml(String.valueOf(amount)) + '</td>';

            html += '</tr>';

            index++;
        }

        html += '</tbody></table>';

        // Invoice total
        html += '<div class="total">';

        html += 'Invoice Total: ' +
            escapeHtml(
                String.valueOf(
                    inv.Total_Amount__c != null
                    ? inv.Total_Amount__c : calculatedTotal
                )
            );

        html += '</div>';

        // Memo
        if (String.isNotBlank(inv.Memo__c)) {

            html += '<p><b>Memo:</b><br/>' +
                escapeHtml(inv.Memo__c) +
                '</p>';
        }

        html += '<p style="margin-top:40px;">' +
                'Thank you for your business.</p>';

        html += '</body></html>';

        return html;
    }

    private static String escapeHtml(String value) {

        if (value == null) {
            return '';
        }

        String result = value.replace('&', '&amp;');
        result = result.replace('<', '&lt;');
        result = result.replace('>', '&gt;');
        result = result.replace('"', '&quot;');
        result = result.replace('\'', '&#39;');

        return result;
    }
}