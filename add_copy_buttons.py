import re

file_path = r'C:\Development\VS Code\Timesheet\Timesheet\main\default\lwc\demoDataSetup\demoDataSetup.html'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

def replacer(match):
    full_match = match.group(0)
    inner_text = match.group(1)
    
    # We want to add copy button if the inner text is enclosed in quotes
    # or if it seems to be an actionable value.
    # Exclude labels like "Email Template Name:" or "Description:" or "Subject:" or "Body:" or "Next" or "Save" or "Go"
    if inner_text.endswith(':'):
        return full_match
    if inner_text in ['Next', 'Save', 'Go', 'Email Templates', 'Classic Email Templates', 'New Template']:
        # Let's handle 'Next', 'Save', 'Go' as non-copyable usually, but they are button names.
        if inner_text in ['Next', 'Save', 'Go']:
            return full_match
            
    # For email template values:
    # "Timesheet Approved Email Templates"
    
    # Actually, the user says "search for 'Email Templates' after this word I need to add copy symbol. Like this every places I want copy symbol"
    
    # We should extract the clean text to copy (without quotes)
    clean_text = inner_text.replace("'", "").replace("\"", "").replace("“", "").replace("”", "").replace("’", "'").strip()
    
    # Escape for HTML attribute
    clean_text_attr = clean_text.replace('"', '&quot;')
    
    button_html = f'<lightning-button-icon icon-name="utility:copy" variant="bare" size="small" class="slds-m-left_xx-small" onclick={{handleCopy}} data-text="{clean_text_attr}"></lightning-button-icon>'
    
    return f'{full_match}{button_html}'

# Only target <strong> tags that are within the accordion sections for the manual steps
start_idx = content.find('<lightning-accordion-section name="emailTemplates"')
if start_idx != -1:
    end_idx = content.find('</lightning-accordion>', start_idx)
    if end_idx != -1:
        prefix = content[:start_idx]
        suffix = content[end_idx:]
        target_content = content[start_idx:end_idx]
        
        # Replace <strong>...</strong> where it's a value
        # Let's only match <strong> that contains quotes, or is a specific value
        def targeted_replacer(match):
            full_match = match.group(0)
            inner_text = match.group(1)
            
            # Skip labels
            if inner_text.endswith(':'):
                return full_match
            # Skip common button clicks if they don't have quotes
            if inner_text in ['Next', 'Save', 'Go', 'Setup']:
                return full_match
                
            clean_text = inner_text.replace("'", "").replace("\"", "").replace("“", "").replace("”", "").replace("’", "'").strip()
            clean_text_attr = clean_text.replace('"', '&quot;')
            button_html = f'<lightning-button-icon icon-name="utility:copy" variant="bare" size="small" class="slds-m-left_xx-small slds-m-right_xx-small" onclick={{handleCopy}} data-text="{clean_text_attr}" title="Copy to Clipboard"></lightning-button-icon>'
            
            return f'{full_match}{button_html}'
            
        modified_target = re.sub(r'<strong>(.*?)</strong>', targeted_replacer, target_content)
        
        new_content = prefix + modified_target + suffix
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print("Updated HTML successfully.")
    else:
        print("End not found")
else:
    print("Start not found")
