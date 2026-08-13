const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'Timesheet/main/default/lwc/demoDataSetup/demoDataSetup.html');
let content = fs.readFileSync(filePath, 'utf8');

const startIdx = content.indexOf('<lightning-accordion-section name="emailTemplates"');
if (startIdx !== -1) {
    const endIdx = content.indexOf('</lightning-accordion>', startIdx);
    if (endIdx !== -1) {
        const prefix = content.substring(0, startIdx);
        const suffix = content.substring(endIdx);
        const targetContent = content.substring(startIdx, endIdx);
        
        const modifiedTarget = targetContent.replace(/<strong>(.*?)<\/strong>/g, (match, innerText) => {
            if (innerText.endsWith(':')) {
                return match;
            }
            if (['Next', 'Save', 'Go', 'Setup'].includes(innerText)) {
                return match;
            }
            
            const cleanText = innerText.replace(/['"“”’]/g, '').trim();
            const cleanTextAttr = cleanText.replace(/"/g, '&quot;');
            
            const buttonHtml = `<lightning-button-icon icon-name="utility:copy" variant="bare" size="small" class="slds-m-left_xx-small slds-m-right_xx-small" onclick={handleCopy} data-text="${cleanTextAttr}" title="Copy to Clipboard"></lightning-button-icon>`;
            
            return `${match}${buttonHtml}`;
        });
        
        const newContent = prefix + modifiedTarget + suffix;
        fs.writeFileSync(filePath, newContent, 'utf8');
        console.log("Updated HTML successfully.");
    } else {
        console.log("End not found");
    }
} else {
    console.log("Start not found");
}
