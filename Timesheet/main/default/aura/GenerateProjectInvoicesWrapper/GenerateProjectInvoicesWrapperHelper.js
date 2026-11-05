({
    navigateToList : function(component, shouldRefresh) {
        component.find('nav').navigate({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Intermediate_Invoice__c',
                actionName: 'list'
            }
        }, true);
        if (shouldRefresh) {
            window.setTimeout($A.getCallback(function() {
                $A.get('e.force:refreshView').fire();
            }), 400);
        }
    }
})
