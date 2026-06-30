public virtual class TriggerHandler {
    
    // the current context of the trigger, overridable in tests
    @TestVisible
    private TriggerContext context;

    // the current context of the trigger (isBefore, isAfter, isInsert, etc)
    @TestVisible
    private Boolean isTriggerExecuting;

    public TriggerHandler() {
        this.setTriggerContext();
    }

    public void run() {
        if (!validateRun()) return;

        // dispatch to the correct handler method
        if (this.context == TriggerContext.BEFORE_INSERT) {
            this.beforeInsert();
        } else if (this.context == TriggerContext.BEFORE_UPDATE) {
            this.beforeUpdate();
        } else if (this.context == TriggerContext.BEFORE_DELETE) {
            this.beforeDelete();
        } else if (this.context == TriggerContext.AFTER_INSERT) {
            this.afterInsert();
        } else if (this.context == TriggerContext.AFTER_UPDATE) {
            this.afterUpdate();
        } else if (this.context == TriggerContext.AFTER_DELETE) {
            this.afterDelete();
        } else if (this.context == TriggerContext.AFTER_UNDELETE) {
            this.afterUndelete();
        }
    }

    private void setTriggerContext() {
        this.isTriggerExecuting = Trigger.isExecuting;
        
        if (Trigger.isExecuting) {
            if (Trigger.isBefore && Trigger.isInsert) {
                this.context = TriggerContext.BEFORE_INSERT;
            } else if (Trigger.isBefore && Trigger.isUpdate) {
                this.context = TriggerContext.BEFORE_UPDATE;
            } else if (Trigger.isBefore && Trigger.isDelete) {
                this.context = TriggerContext.BEFORE_DELETE;
            } else if (Trigger.isAfter && Trigger.isInsert) {
                this.context = TriggerContext.AFTER_INSERT;
            } else if (Trigger.isAfter && Trigger.isUpdate) {
                this.context = TriggerContext.AFTER_UPDATE;
            } else if (Trigger.isAfter && Trigger.isDelete) {
                this.context = TriggerContext.AFTER_DELETE;
            } else if (Trigger.isAfter && Trigger.isUndelete) {
                this.context = TriggerContext.AFTER_UNDELETE;
            }
        }
    }

    private Boolean validateRun() {
        if (!this.isTriggerExecuting) {
            return false;
        }
        return true;
    }

    // context-specific methods for override
    protected virtual void beforeInsert(){}
    protected virtual void beforeUpdate(){}
    protected virtual void beforeDelete(){}
    protected virtual void afterInsert(){}
    protected virtual void afterUpdate(){}
    protected virtual void afterDelete(){}
    protected virtual void afterUndelete(){}

    // possible trigger contexts
    @TestVisible
    private enum TriggerContext {
        BEFORE_INSERT, BEFORE_UPDATE, BEFORE_DELETE,
        AFTER_INSERT, AFTER_UPDATE, AFTER_DELETE,
        AFTER_UNDELETE
    }
}
