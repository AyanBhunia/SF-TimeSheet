global with sharing class test_merge_acc_con {
    
    @InvocableMethod(label='Merge Account & Contact Info' description='Processes matching Account and Contact data')
    public static List<TestMergeAccConData> mergeAccCon(List<TestMergeAccConData> requests) {
        List<TestMergeAccConData> responses = new List<TestMergeAccConData>();
        for(TestMergeAccConData req : requests) {
            TestMergeAccConData resp = new TestMergeAccConData();
            // Here, simply passing the values through; add your merging logic as needed
            resp.accountFirstName = req.accountFirstName;
            resp.accountLastName  = req.accountLastName;
            resp.contactFirstName = req.contactFirstName;
            resp.contactLastName  = req.contactLastName;
            resp.contactEmail     = req.contactEmail;
            responses.add(resp);
        }
        return responses;
    }
}