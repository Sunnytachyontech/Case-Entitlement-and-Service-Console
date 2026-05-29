trigger CaseTrigger on Case (before insert, before update, after insert, after update) {

    if (Trigger.isBefore && Trigger.isInsert) {
        CaseTriggerHandler.onBeforeInsert(Trigger.new);
    }
    
    if (Trigger.isBefore && Trigger.isUpdate) {
        CaseTriggerHandler.onBeforeUpdate(Trigger.new, Trigger.oldMap);
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        CaseTriggerHandler.onAfterInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        CaseTriggerHandler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}