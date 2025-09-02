@isTest
private class AWSS3UtilitiesTest {

    @isTest
    static void testGetRecordApiName() {
        String apiName = AWSS3Utilities.getRecordApiName(UserInfo.getUserId());
        System.assertEquals('User', apiName, 'Should return correct sObject API name');
    }

    @isTest
    static void testGetSalesforceS3Files() {

        S3_File__c file = new S3_File__c(
            Parent_Id__c = UserInfo.getUserId(),
            sObject_Type__c = 'User',
            File_Name__c = 'test.txt',
            Key__c = 'test-key',
            Visibility__c = 'external',
            Object_URL__c = 'https://test-bucket.s3.amazonaws.com/test-key',
            Versions__c = 1
        );
        insert file;

        List<S3_File__c> files = AWSS3Utilities.getSalesforceS3Files(UserInfo.getUserId(), 'external');
        System.assert(!files.isEmpty(), 'Should return at least one file');
    }

    @isTest
    static void testGetSalesforceApplicationS3Files() {

        S3_File__c file = new S3_File__c(
            Parent_Id__c = UserInfo.getUserId(),
            sObject_Type__c = 'User',
            File_Name__c = 'test.txt',
            Key__c = 'test-key',
            Visibility__c = 'external',
            S3_Path__c = 'test-path',
            Object_URL__c = 'https://test-bucket.s3.amazonaws.com/test-key',
            Versions__c = 1
        );
        insert file;

        List<S3_File__c> files = AWSS3Utilities.getSalesforceApplicationS3Files(UserInfo.getUserId(), 'test-path');
        System.assert(!files.isEmpty(), 'Should return at least one file');
    }

    @isTest
    static void testCreateSalesforceS3File() {
        S3_File__c file = new S3_File__c(
            Parent_Id__c = UserInfo.getUserId(),
            sObject_Type__c = 'User',
            File_Name__c = 'newfile.txt',
            Key__c = 'new-key',
            Object_URL__c = 'https://test-bucket.s3.amazonaws.com/new-key'
        );
        S3_File__c result = AWSS3Utilities.createSalesforceS3File(file);
        S3_File__c result2 = AWSS3Utilities.createSalesforceS3File(file);

        S3_File__c result2WithVersion = [SELECT Id, Versions__c FROM S3_File__c WHERE Id =: result2.Id];
        System.assertNotEquals(null, result.Id, 'File should be inserted');
        System.assertEquals(2, result2WithVersion.Versions__c, 'Version should be 2');
    }

    @isTest
    static void testViewFileAndPostFile() {
        // These methods return a presigned URL string
        String viewUrl = AWSS3Utilities.viewFile('test-key');
        String postUrl = AWSS3Utilities.postFile('test-key');
        System.assertNotEquals(null, viewUrl, 'View URL should not be null');
        System.assertNotEquals(null, postUrl, 'Post URL should not be null');
    }

    @isTest
    static void testDeleteFile() {

        S3_File__c file = new S3_File__c(
            Parent_Id__c = UserInfo.getUserId(),
            sObject_Type__c = 'User',
            File_Name__c = 'newfile.txt',
            Key__c = 'new-key',
            Object_URL__c = 'https://test-bucket.s3.amazonaws.com/new-key'
        );

        insert file;

        Test.setMock(HttpCalloutMock.class, new AWSS3MockCallout());

        S3_File__c s3File = [SELECT Id, Key__c FROM S3_File__c LIMIT 1];
        
        Test.startTest();
        Boolean deleted = AWSS3Utilities.deleteFile(file.Key__c, file.Id);
        Test.stopTest();
        
        System.assertEquals(true, deleted, 'File should be deleted');
        System.assertEquals('DELETE', AWSS3MockCallout.lastMethod, 'Should perform DELETE method');
        System.assertNotEquals(null, AWSS3MockCallout.lastEndpoint, 'Endpoint should not be null');
    }

    @isTest
    static void testListFiles() {
        // Register the mock response
        Test.setMock(HttpCalloutMock.class, new AWSS3MockCallout());

        // Call the method under test
        Test.startTest();
        List<AWSS3Utilities.File> files = AWSS3Utilities.listFiles('Account/001abc/');
        Test.stopTest();

        // Validate the results
        System.assertEquals(2, files.size(), 'Should return 2 files');

        AWSS3Utilities.File firstFile = files[0];
        System.assertEquals('Account/001abc/test1.jpg', firstFile.get('Key'), 'First file key mismatch');
        System.assertEquals('1024', firstFile.get('Size'), 'First file size mismatch');

        AWSS3Utilities.File secondFile = files[1];
        System.assertEquals('Account/001abc/test2.jpg', secondFile.get('Key'), 'Second file key mismatch');
        System.assertEquals('2048', secondFile.get('Size'), 'Second file size mismatch');
    }

    @isTest
    static void testGetSignatureKey() {
        String key = 'test-secret-key';
        String dateStamp = '20250805';
        String regionName = 'us-east-1';
        String serviceName = 's3';

        Blob signingKey = AWSS3Utilities.getSignatureKey(key, dateStamp, regionName, serviceName);

        System.assertNotEquals(null, signingKey, 'Signing key should not be null');
        System.assert(signingKey.size() > 0, 'Signing key blob should not be empty');
    }

    @isTest
    static void testGetFileSizeLimit() {
        AWSS3Utilities.getFileSizeLimit('');
    }
}