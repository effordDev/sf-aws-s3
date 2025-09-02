@isTest
private class AWSS3BucketVisibilityPicklistTest 
{
    @isTest
    private static void getDefaultValueTest()
    {
        AWSS3BucketVisibilityPicklist picklist = new AWSS3BucketVisibilityPicklist();
    
        VisualEditor.DataRow defaultValue = picklist.getDefaultValue();

        System.assertEquals('external', defaultValue.getLabel(), 'The default label should be "external".');
        System.assertEquals('external', defaultValue.getValue(), 'The default value should be "external".');
    }

    @isTest
    private static void getValuesTest()
    {
        AWSS3BucketVisibilityPicklist picklist = new AWSS3BucketVisibilityPicklist();

        VisualEditor.DynamicPickListRows values = picklist.getValues();
    }
}