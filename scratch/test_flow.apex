try {
    DemoDataController.createDemoData();
    System.debug('SUCCESS');
} catch (Exception e) {
    System.debug('ERROR_MSG: ' + e.getMessage());
    System.debug('ERROR_STACK: ' + e.getStackTraceString());
}
