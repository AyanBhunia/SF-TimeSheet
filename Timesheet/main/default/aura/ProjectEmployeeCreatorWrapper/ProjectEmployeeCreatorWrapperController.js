({
    handleClose : function(component, event) {
        var saved = event.getParam && event.getParam('saved');
        // Go to the Project Employee list (last used list view). Replacing this page keeps
        // Back from reopening the modal and works when the page was opened from a bookmark.
        component.find('nav').navigate({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'dbt__Project_Employee__c',
                actionName: 'list'
            }
        }, true);
        if (saved) {
            // Refresh once the list is shown so the new records appear
            window.setTimeout($A.getCallback(function() {
                $A.get('e.force:refreshView').fire();
            }), 500);
        }
    }
})
