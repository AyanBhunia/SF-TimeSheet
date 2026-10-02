<?xml version="1.0" encoding="UTF-8"?>
<Workflow xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldUpdates>
        <fullName>PTO_Set_Approved</fullName>
        <description>Leave approval: final approval sets Status to Approved.</description>
        <field>Status__c</field>
        <literalValue>Approved</literalValue>
        <name>PTO Set Approved</name>
        <notifyAssignee>false</notifyAssignee>
        <operation>Literal</operation>
        <protected>false</protected>
        <reevaluateOnChange>false</reevaluateOnChange>
    </fieldUpdates>
    <fieldUpdates>
        <fullName>PTO_Set_New</fullName>
        <description>Leave approval: rejection sets Status back to New.</description>
        <field>Status__c</field>
        <literalValue>New</literalValue>
        <name>PTO Set New</name>
        <notifyAssignee>false</notifyAssignee>
        <operation>Literal</operation>
        <protected>false</protected>
        <reevaluateOnChange>false</reevaluateOnChange>
    </fieldUpdates>
</Workflow>
