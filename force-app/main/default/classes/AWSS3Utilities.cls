/**
 * Utility class for AWS S3 operations in Salesforce.
 * Handles file upload, deletion, listing, and presigned URL generation.
*/
public without sharing class AWSS3Utilities {
    /**
     * Expiry time for presigned URLs (in seconds).
    */
    private Final static Integer PRESIGNED_URL_EXPIRES = 60;

    /**
     * Returns a presigned URL for viewing a file.
     * @param key S3 key for the file.
     * @return Presigned URL string.
    */
    @AuraEnabled
    public static String viewFile(String key) {
        
        // String url = createPresignedUrlForView(key);
        String method = 'GET';
        String url = createPresignedUrl(method, key);

        system.debug('view url');
        system.debug(url);

        return url;
    }

    /**
     * Returns a presigned URL for uploading a file.
     * @param key S3 key for the file.
     * @return Presigned URL string.
    */
    @AuraEnabled
    public static String postFile(String key) {

        // String url = createPresignedUrlForView(key);
        String method = 'PUT';
        String url = createPresignedUrl(method, key);

        system.debug('post url');
        system.debug(url);

        return url;
    }

    /**
     * Deletes a file from S3 and removes its record from Salesforce.
     * @param key S3 key for the file.
     * @param id Salesforce record Id for the file.
     * @return True if deleted successfully, false otherwise.
    */
    @AuraEnabled
    public static Boolean deleteFile(String key, String id){

        AWS_S3_Setting__mdt creds = getCreds('');

        String accessKey = creds.Access_Key__c;
        String secretKey = creds.Secret_Access_Key__c;
        String bucketName =  creds.Bucket__c;
        String bucketRegion = creds.Region__c; 

        Boolean isDeleted = false;

        try {
            Datetime currentDateTime = Datetime.now();
            String dateOnly = currentDateTime.formatGmt('yyyyMMdd');
            String xAmzDate = currentDateTime.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
            String credentialScope = dateOnly + '/' + bucketRegion + '/s3/aws4_request';
            String xAmzCredentialStr = accessKey + '/' + credentialScope;
            String xAmzSignedHeaders = 'host;x-amz-date';
            String host = bucketName + '.s3.' + bucketRegion + '.amazonaws.com';
    
            // Canonical request for DELETE
            String canonicalRequest =
                'DELETE\n' +
                UriEncode('/' + key, false) + '\n' +
                '\n' +
                'host:' + host + '\n' +
                'x-amz-date:' + xAmzDate + '\n' +
                '\n' +
                'host;x-amz-date\n' +
                'UNSIGNED-PAYLOAD';
    
            // String to sign
            String stringToSign = 'AWS4-HMAC-SHA256\n' +
                xAmzDate + '\n' +
                credentialScope + '\n' +
                EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(canonicalRequest)));
    
            // Generate the signing key
            Blob dateKey = Crypto.generateMac('hmacSHA256', Blob.valueOf(dateOnly), Blob.valueOf('AWS4' + secretKey));
            Blob dateRegionKey = Crypto.generateMac('hmacSHA256', Blob.valueOf(bucketRegion), dateKey);
            Blob dateRegionServiceKey = Crypto.generateMac('hmacSHA256', Blob.valueOf('s3'), dateRegionKey);
            Blob signingKey = Crypto.generateMac('hmacSHA256', Blob.valueOf('aws4_request'), dateRegionServiceKey);
    
            // Generate the signature
            Blob signature = Crypto.generateMac('hmacSHA256', Blob.valueOf(stringToSign), signingKey);
            String signatureStr = EncodingUtil.convertToHex(signature);
    
            // Create and send the HTTP request
            HttpRequest httpRequest = new HttpRequest();
                httpRequest.setMethod('DELETE');
                httpRequest.setEndpoint('https://' + host + '/' + UriEncode(key, true));
                httpRequest.setHeader('Authorization', 'AWS4-HMAC-SHA256 Credential=' + accessKey + '/' + credentialScope + ', SignedHeaders=' + xAmzSignedHeaders + ', Signature=' + signatureStr);
                httpRequest.setHeader('x-amz-date', xAmzDate);
                httpRequest.setHeader('x-amz-content-sha256', 'UNSIGNED-PAYLOAD');
    
            Http http = new Http();
            HttpResponse res = http.send(httpRequest);

            system.debug(res.getStatusCode() + ' ' + res.getStatus());
            system.debug(res.getBody());
    
            if (res.getStatusCode() == 204) { // 204 No Content means the deletion was successful
                isDeleted = true;

                S3_File__c s3FileToDelete = new S3_File__c();
                    s3FileToDelete.Id = id;
                    s3FileToDelete.Deleted__c = true;
                update s3FileToDelete;
            } else {
                System.debug('Error: ' + res.getStatusCode() + ' ' + res.getStatus());
                System.debug('Response Body: ' + res.getBody());
            }
    
        } catch (Exception e) {
            System.debug('Exception: ' + e.getMessage());
        }
    
        return isDeleted;
    }
    
    /**
     * Lists files for the specified S3 path prefix.
     * @param prefix S3 path prefix.
     * @return List of File objects.
    */
    @AuraEnabled
    public static List<File> listFiles(String prefix) {

        AWS_S3_Setting__mdt creds = getCreds('');

        String accessKey = creds.Access_Key__c;
        String secretKey = creds.Secret_Access_Key__c;
        String bucketName =  creds.Bucket__c;
        String bucketRegion = creds.Region__c; 

        List<String> fileNames = new List<String>();

        String endpoint = 'https://' + bucketName + '.s3.' + bucketRegion + '.amazonaws.com/?prefix=' + EncodingUtil.urlEncode(prefix, 'UTF-8');
        HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint(endpoint);

        // Add AWS Signature (for simplicity, you might need to use a library or custom implementation)
        String dateString = Datetime.now().formatGMT('EEE, dd MMM yyyy HH:mm:ss') + ' GMT';
            req.setHeader('Date', dateString);

        // Authorization header: AWS <AccessKey>:<Signature>
        String stringToSign = 'GET\n\n\n' + dateString + '\n/' + bucketName + '/';
        String signature = EncodingUtil.base64Encode(Crypto.generateMac('HmacSHA1', Blob.valueOf(stringToSign), Blob.valueOf(secretKey)));
            req.setHeader('Authorization', 'AWS ' + accessKey + ':' + signature);

        Http http = new Http();
        HttpResponse res = http.send(req);

        Dom.Document doc = res.getBodyDocument();
        System.debug(doc);
        //Retrieve the root element for this document.
        Dom.XMLNode result = doc.getRootElement();
        
        List<File> files = new List<File>();

        // loop through the child elements.
        // deserialize the Contents xml into a list of files
        for (Dom.XMLNode child : result.getChildElements()) {
           
           System.debug(child);
          
           File file = new File();
           
            for (Dom.XMLNode content : child.getChildElements()){
                System.debug(content.getName() + ' => ' + content.getText());
                file.put(content.getName(), content.getText());
            }

            if (file.get('Key') != null) {
                files.add(file);
            }
        }

        System.debug('Files found: ' + files.size());
        System.debug('Files: ' + files);
        System.debug(files);
        return files;
    }

    /**
     * Determines if instance is production
     * @return Boolean for production instance - true if prod.
    */
    private static Boolean isProd() {
        Organization org = [
            SELECT Id, Name, IsSandbox 
            FROM Organization
        ];

        return !org.IsSandbox;
    }

    /**
     * Encodes aws key
     * @return String - encodedKey.
    */
    private static String encodeS3Key(String key) {
    
        String encoded = EncodingUtil.urlEncode(key, 'UTF-8');
    
        encoded = encoded.replace('+', '%20');
        
        encoded = encoded.replace('%2F', '/');
        return encoded;
    }


    /**
     * Generates a presigned URL for S3 operations.
     * @param method HTTP method (GET, PUT, DELETE).
     * @param key S3 key for the file.
     * @return Presigned URL string.
    */
    private static String createPresignedUrl(String method, String key) {
        AWS_S3_Setting__mdt creds = getCreds('');

        String accessKey = creds.Access_Key__c;
        String secretKey = creds.Secret_Access_Key__c;
        String bucketName =  creds.Bucket__c;
        String bucketRegion = creds.Region__c; 

        String encodedKey = encodeS3Key(key);

        // String location = createBaseUrl(creds) + key;
        String location = createBaseUrl(creds) + encodedKey;

        DateTime currentDateTime = DateTime.now();
        String dateOnly = currentDateTime.formatGmt('yyyyMMdd');
        String req =  dateOnly + '/'+ bucketRegion +'/s3/aws4_request';
        String xAmzCredentialStr = accessKey + '/' + req;
        String xAmzDate = currentDateTime.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
        String xAmzSignedHeaders = 'host';
        String host = bucketName + '.s3.'+ bucketRegion +'.amazonaws.com';

        // String canonicalRequest = method + '\n'+'/' + key + '\n';
        // String encodedKey = EncodingUtil.urlEncode(key, 'UTF-8').replace('+', '%20');
        String canonicalRequest = method + '\n'+'/' + encodedKey + '\n';
        
        canonicalRequest += UriEncode('X-Amz-Algorithm', true) + '=' + UriEncode('AWS4-HMAC-SHA256', true) + '&' +
            UriEncode('X-Amz-Credential', true) + '=' + UriEncode(xAmzCredentialStr, true) + '&' +
            UriEncode('X-Amz-Date', true) + '=' + UriEncode(xAmzDate, true) + '&' +
            UriEncode('X-Amz-Expires', true) + '=' + UriEncode(String.valueOf(PRESIGNED_URL_EXPIRES), true) + '&' +
            UriEncode('X-Amz-SignedHeaders', true) + '=' + UriEncode(xAmzSignedHeaders, true) + '\n';

            canonicalRequest += 'host:'+host + '\n\n' +
            'host\n' +
            'UNSIGNED-PAYLOAD';
     
        String stringToSign = 'AWS4-HMAC-SHA256\n' +
            xAmzDate + '\n' +
            req + '\n' +
            EncodingUtil.convertToHex(
                Crypto.generateDigest('SHA-256', Blob.valueOf(canonicalRequest))
            );
		
        Blob dateKey = Crypto.generateMac('hmacSHA256', Blob.valueOf(dateOnly), Blob.valueOf('AWS4' + secretKey));
        Blob dateRegionKey = Crypto.generateMac('hmacSHA256', Blob.valueOf(bucketRegion), dateKey);
        Blob dateRegionServiceKey = Crypto.generateMac('hmacSHA256', Blob.valueOf('s3'), dateRegionKey);
        Blob signingKey = Crypto.generateMac('hmacSHA256', Blob.valueOf('aws4_request'), dateRegionServiceKey);
     
        Blob signature = Crypto.generateMac('hmacSHA256', Blob.valueOf(stringToSign), signingKey);
        String signatureStr = EncodingUtil.convertToHex(signature);
     
        String result = location + 
        '?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=' + EncodingUtil.urlEncode(xAmzCredentialStr, 'UTF-8') + 
        '&X-Amz-Date=' + xAmzDate + 
        '&X-Amz-Expires=' + String.valueOf(PRESIGNED_URL_EXPIRES) + 
        '&X-Amz-Signature=' + signatureStr + '&X-Amz-SignedHeaders=host';

		return result;
    }

    /**
     * Retrieves AWS S3 credentials from custom metadata.
     * @param cred DeveloperName for the credential record.
     * @return AWS_S3_Setting__mdt record.
    */
    private static AWS_S3_Setting__mdt getCreds(String cred) {

        Boolean isProd = isProd();

        system.debug('isProd');
        system.debug(isProd);

        String query = 'SELECT '
                + 'Id, '
                + 'DeveloperName, '
                + 'Bucket__c, '
                + 'Identity_Pool_Id__c, '
                + 'Region__c, '
                + 'Access_Key__c, '
                + 'Production__c, '
                + 'Secret_Access_Key__c '
            + 'FROM AWS_S3_Setting__mdt ' 
            + ' WHERE Production__c =: isProd';

        if (cred != null && cred != '') {
            query += ' AND DeveloperName = \'' + String.escapeSingleQuotes(cred) + '\'';
        }

        query += ' LIMIT 1';
        
        AWS_S3_Setting__mdt credentials = Database.query(query);

        system.debug('credentials');
        system.debug('credentials.DeveloperName ' + credentials.DeveloperName);
        system.debug('credentials.Bucket__c ' + credentials.Bucket__c);
        system.debug('credentials.Region__c ' + credentials.Region__c);
        system.debug('credentials.Production__c ' + credentials.Production__c);

        return credentials;
    }

    /**
     * Retrieves AWS S3 Org wide File size limit from custom metadata.
     * @param cred DeveloperName for the credential record.
     * @return AWS_S3_Setting__mdt record.
    */
    @AuraEnabled
    public static AWS_S3_Setting__mdt getFileSizeLimit(String cred) {

        String query = 'SELECT '
                + 'Id, '
                + 'DeveloperName, '
                + 'File_Size_Limit_Mb__c '
            + 'FROM AWS_S3_Setting__mdt';

        if (cred != null && cred != '') {
            query += ' WHERE DeveloperName = \'' + String.escapeSingleQuotes(cred) + '\'';
        }

        query += ' LIMIT 1';

        AWS_S3_Setting__mdt credentials = Database.query(query);

        return credentials;
    }
    
    /**
     * Gets the API name of a Salesforce record.
     * @param recordId Salesforce record Id.
     * @return API name string.
    */
    @AuraEnabled
    public static string getRecordApiName(Id recordId) {
        return recordId.getSObjectType().getDescribe().getName();
    }

    /**
     * Creates the base S3 URL from credentials.
     * @param cred AWS_S3_Setting__mdt record.
     * @return Base S3 URL string.
    */
    private static String createBaseUrl(AWS_S3_Setting__mdt cred) {
        return 'https://' + cred.Bucket__c + '.s3.' + cred.Region__c + '.amazonaws.com/';
    }

    /**
     * Encodes a string for S3 URI requirements. Apex EncodingUtil.urlEncode differs from AWS S3 documentation Uri encoding
     * @param input String to encode.
     * @param encodeSlash Whether to encode slashes.
     * @return Encoded string.
    */
    private static String UriEncode(String input, Boolean encodeSlash) {
        String result = '';
    
        for (Integer i = 0; i < input.length(); i++) {
            String ch = input.substring(i, i + 1);
    
            if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a'
               && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' ||
               ch == '-' || ch == '~' || ch == '.') {
               result += ch;
            } else if (ch == '/') {
               result += encodeSlash ? '%2F' : ch;
            } else {
                String hexValue = EncodingUtil.convertToHex(Blob.valueOf(ch)).toUpperCase();
    
                if (hexValue.length() == 2) {
                    result += '%' + hexValue;
                } else if (hexValue.length() == 4) {
                    result += '%' + hexValue.substring(0, 2) + '%' + hexValue.substring(2);
                }
            }
        }
    
       return result;
    }

    /**
     * Generates the signature key for AWS V4 signing.
     * @param key Secret key.
     * @param dateStamp Date stamp.
     * @param regionName AWS region.
     * @param serviceName AWS service name.
     * @return Signing key as Blob.
    */
    @testVisible
    private static Blob getSignatureKey(String key, String dateStamp, String regionName, String serviceName) {
        Blob kDate = Crypto.generateMac('HMACSHA256', Blob.valueOf(dateStamp), Blob.valueOf('AWS4' + key));
        Blob kRegion = Crypto.generateMac('HMACSHA256', Blob.valueOf(regionName), kDate);
        Blob kService = Crypto.generateMac('HMACSHA256', Blob.valueOf(serviceName), kRegion);
        Blob kSigning = Crypto.generateMac('HMACSHA256', Blob.valueOf('aws4_request'), kService);
        return kSigning;
    }

    /**
     * File wrapper class for S3 file metadata.
    */
    public class File {
        @AuraEnabled public String Name;
        @AuraEnabled public String Key;
        @AuraEnabled public String LastModified;
        @AuraEnabled public String ETag;
        @AuraEnabled public String Size;
        @AuraEnabled public String StorageClass;

        public void put(String key, String value){
            if(key == 'Key') {
                this.Key = value;
                this.Name = value.substring(value.lastIndexOf('/')+1);
            }
            if(key == 'LastModified') this.LastModified = value;
            if(key == 'ETag') this.ETag = value;
            if(key == 'Size') this.Size = value;
            if(key == 'StorageClass') this.StorageClass = value;
        }

        public String get(String key){
            if(key == 'Key') return this.Key;
            if(key == 'Name') return this.Name;
            if(key == 'LastModified') return this.LastModified;
            if(key == 'ETag') return this.ETag;
            if(key == 'Size') return this.Size;
            if(key == 'StorageClass') return this.StorageClass;
            return '';
        }
    }

    /**
     * Creates or updates a Salesforce S3 file record.
     * @param s3File S3_File__c record.
     * @return Created or updated S3_File__c record.
    */
    @AuraEnabled
    public static S3_File__c createSalesforceS3File(S3_File__c s3File) {

        system.debug('s3File');
        system.debug(s3File);

        List<S3_File__c> existingS3Files = [
            SELECT Id,
                Versions__c
            FROM S3_File__c
            WHERE Parent_Id__c =: s3File.Parent_Id__c
                AND sObject_Type__c =: s3File.sObject_Type__c
                AND Key__c =: s3File.Key__c
                AND Object_URL__c =: s3File.Object_URL__c
                AND Deleted__c = false
        ];

        if (existingS3Files.isEmpty()) {
                s3File.Versions__c = 1;
            insert s3File;
            return s3File;
        } else {
            S3_File__c existingS3File = existingS3Files[0];
                existingS3File.Versions__c = existingS3File.Versions__c + 1;
            update existingS3File;
            return existingS3File;
        }
    }

    /**
     * Retrieves Salesforce S3 file records for a given record Id.
     * @param recordId Salesforce record Id.
     * @param visibility top level bucket the files are contained in.
     * @return List of S3_File__c records.
    */
    @AuraEnabled
    public static List<S3_File__c> getSalesforceS3Files(Id recordId, String visibility) {

        String sObjectDeveloperName = recordId.getSObjectType().getDescribe().getName();

        return [
            SELECT Id,
                Parent_Id__c,
                File_Info__c,
                Visibility__c,
                File_Extension__c,
                sObject_Type__c,
                Versions__c,
                File_Name__c,
                CreatedDate,
                S3_Path__c,
                File_Last_Modified_Epoch__c,
                File_Last_Modified_Date__c,
                Key__c,
                Size_Label__c,
                Size_Bytes__c,
                Size_Kilobytes__c,
                Size_Megabytes__c,
                Type__c,
                Object_URL__c,
                Deleted__c
            FROM S3_File__c
            WHERE Parent_Id__c =: recordId 
                AND sObject_Type__c =: sObjectDeveloperName   
                AND Visibility__c =: visibility
                AND Deleted__c = false
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * Retrieves Salesforce S3 file records for a given record Id.
     * @param recordId Salesforce record Id.
     * @param path Path to files.
     * @return List of S3_File__c records.
    */
    @AuraEnabled
    public static List<S3_File__c> getSalesforceApplicationS3Files(
        Id recordId, 
        String path
    ) {

        String sObjectDeveloperName = recordId.getSObjectType().getDescribe().getName();

        return [
            SELECT Id,
                Parent_Id__c,
                File_Info__c,
                File_Extension__c,
                sObject_Type__c,
                Versions__c,
                File_Name__c,
                CreatedDate,
                S3_Path__c,
                File_Last_Modified_Epoch__c,
                File_Last_Modified_Date__c,
                Key__c,
                Size_Label__c,
                Size_Bytes__c,
                Size_Kilobytes__c,
                Size_Megabytes__c,
                Type__c,
                Object_URL__c,
                Deleted__c
            FROM S3_File__c
            WHERE Parent_Id__c =: recordId 
                AND sObject_Type__c =: sObjectDeveloperName   
                AND S3_Path__c =: path
                AND Visibility__c = 'external'
                AND Deleted__c = false
            ORDER BY CreatedDate DESC
        ];
    }
}