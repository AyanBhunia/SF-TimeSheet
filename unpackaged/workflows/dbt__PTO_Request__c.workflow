<?xml version="1.0" encoding="UTF-8"?>
<Workflow xmlns="http://soap.sforce.com/2006/04/metadata">
    <alerts>
        <fullName>PTO_Request_Approved</fullName>
        <description>Leave approval: tells the employee (request owner) the request was approved.</description>
        <protected>false</protected>
        <recipients>
            <type>owner</type>
        </recipients>
        <senderType>CurrentUser</senderType>
        <template>PTO_Emails/PTO_Approved</template>
    </alerts>
    <alerts>
        <fullName>PTO_Request_Rejected</fullName>
        <description>Leave approval: tells the employee (request owner) the request was rejected, with the reason.</description>
        <protected>false</protected>
        <recipients>
            <type>owner</type>
        </recipients>
        <senderType>CurrentUser</senderType>
        <template>PTO_Emails/PTO_Rejected</template>
    </alerts>
    <alerts>
        <fullName>PTO_Request_Submitted</fullName>
        <description>Leave approval: confirms to the employee (request owner) that the request was sent for approval.</description>
        <protected>false</protected>
        <recipients>
            <type>owner</type>
        </recipients>
        <senderType>CurrentUser</senderType>
        <template>PTO_Emails/PTO_Submit_Receipt</template>
    </alerts>
    <fieldUpdates>
        <fullName>PTO_Set_Approved</fullName>
        <description>Leave approval: final approval sets Status to Approved.</description>
        <field>dbt__Status__c</field>
        <literalValue>Approved</literalValue>
        <name>PTO Set Approved</name>
        <notifyAssignee>false</notifyAssignee>
        <operation>Literal</operation>
        <protected>false</protected>
        <reevaluateOnChange>false</reevaluateOnChange>
    </fieldUpdates>
    <fieldUpdates>
        <fullName>PTO_Set_Rejected</fullName>
        <description>Leave approval: rejection sets Status to Rejected.</description>
        <field>dbt__Status__c</field>
        <literalValue>Rejected</literalValue>
        <name>PTO Set Rejected</name>
        <notifyAssignee>false</notifyAssignee>
        <operation>Literal</operation>
        <protected>false</protected>
        <reevaluateOnChange>false</reevaluateOnChange>
    </fieldUpdates>
</Workflow>
