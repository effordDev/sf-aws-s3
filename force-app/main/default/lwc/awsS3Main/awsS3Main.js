import { api, track, LightningElement } from 'lwc';
import LightningAlert from 'lightning/alert';
import { fileTypesMap, createObjectUrlFromPresignedUrl } from 'c/awsS3Utilities';
import getRecordApiName from '@salesforce/apex/AWSS3Utilities.getRecordApiName'
import postFile from '@salesforce/apex/AWSS3Utilities.postFile'
import createSalesforceS3File from '@salesforce/apex/AWSS3Utilities.createSalesforceS3File'
import getSalesforceS3Files from '@salesforce/apex/AWSS3Utilities.getSalesforceS3Files'
import getFileSizeLimit from '@salesforce/apex/AWSS3Utilities.getFileSizeLimit'

export default class AwsS3Main extends LightningElement {
    
    @api recordId
    @api bucketVisibility = 'external'
    @api label = 'Files'

    @api isTableView = false
    @api allowUpload = false
    @api allowView = false
    @api allowDelete = false

    files = []

    settings = {}
    recordApiName = ''

    isLoading = false
    initiated = false

    showLoadingModal = false
    uploadProgress = 0
    uploadProgressTotal = 0

    modalMessage = ''

    get prefix() {
        return `${this.recordApiName}/${this.recordId}/${this.bucketVisibility}`
    }
    get header() {
        return `${capitalize(this.bucketVisibility)} Files`
    }
    get progressBarValue() {

        if (this.uploadProgressTotal === 0) {
            return 100;
        }

        return isNaN((this.uploadProgress / this.uploadProgressTotal) * 100) ? 0 
        : ((this.uploadProgress / this.uploadProgressTotal) * 100).toFixed(2)
    }
    get fileSizeLimitMb() {
        return this.settings?.File_Size_Limit_Mb__c
    }

    async connectedCallback() {
        try {

            this.initiated = false

            this.recordApiName = await getRecordApiName({
                recordId: this.recordId
            })

            await this.fetchSettings()
    
            await this.fetchSalesforceS3Files()

        } catch (error) {
            console.error(error)
        } finally {
            this.initiated = true
        }
        
    }

    async handleUpload(event) {

        console.log(event.target.files.length)

        if (event.target.files.length > 1) {
            await LightningAlert.open({
                message: 'You can only upload one file at a time.',
                theme: 'error',
                label: 'Error!',
            });
            return;
        }
    
        try {

            const file = event.detail.files[0]

            const fileSize = (file.size / 1024 / 1024)

            if (fileSize > this.fileSizeLimitMb) {
                await LightningAlert.open({
                    message: `The selected file is too large (${fileSize.toFixed(2)}MB). Please select a file under ${this.fileSizeLimitMb}MB`,
                    theme: 'error', // a red theme intended for error states
                    label: 'Error!', // this is the header text
                });

                return
            }

            this.modalMessage = 'Uploading file...'
            this.showLoadingModal = true

            const results = await this.uploadFile(file)
    
            // console.log(file)
    
            // console.log('upload complete => ')
            // console.log({results})

            const s3File = {
                Parent_Id__c: this.recordId,
                sObject_Type__c: this.recordApiName,
                Visibility__c: this.bucketVisibility,
                File_Name__c: results.Name,
                S3_Path__c: results.Key.substring(0, results.Key.lastIndexOf('/')),
                Key__c: results.Key,
                Object_URL__c: results.objectUrl,
                File_Last_Modified_Epoch__c: (file.lastModified).toString(),
                Size_Bytes__c: (file.size).toString(),
                Type__c: file.type
            }

            const s3FileResult = await createSalesforceS3File({
                s3File
            })
    
            // console.log({
            //     s3FileResult
            // })
    
            await this.fetchSalesforceS3Files()
            this.modalMessage = 'File uploaded successfully.'
        } catch (error) {

            this.modalMessage = 'An error has occurred.'
            
            console.error('error ', error)
            
            await LightningAlert.open({
                message: error?.body?.message || error?.message || 'An unknown error occurred.',
                theme: 'error',
                label: 'Error!',
            });
        } finally {

        }
    }

    async uploadFile(file) {

        const key = `${this.prefix}/${file.name}`;

        const fileData = {
            Name: file.name,
            Type: file.type,
            Method: 'PUT',
            Key: key,
            length: file.size,
            visibility: this.bucketVisibility
        };

        const signedUrl = await postFile({ key })

        console.log({ signedUrl });

        const result = await this.performUpload(file, signedUrl, fileData);
        return result;
    }

    async performUpload(file, signedUrl, fileData) {

        return new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();

            xhr.open('PUT', signedUrl, true);
            xhr.setRequestHeader('Content-Type', file.type);

            xhr.upload.onprogress = (event) => {
                console.log({event})
                if (event.lengthComputable) {

                    this.uploadProgress = event.loaded;
                    this.uploadProgressTotal = event.total;
                }
            };

            xhr.onload = () => {
                if (xhr.status === 200 || xhr.status === 204) {
                    console.log('Upload success:', xhr.responseText);

                    fileData.objectUrl = createObjectUrlFromPresignedUrl(signedUrl)
                    resolve(fileData);
                } else {
                    console.error('Upload failed with status:', xhr.status);
                    reject(`Upload failed: ${xhr.status}`);
                }
            };

            xhr.onerror = () => {
                console.error('Network error during upload.');
                reject('Network error during upload.');
            };

            xhr.send(file);
        });
    }

    async fetchSalesforceS3Files() {
        try {
            this.isLoading = true

            this.files = (await getSalesforceS3Files({
                recordId: this.recordId,
                visibility: this.bucketVisibility
            })).map(file => {
                    file.icon = `doctype:${fileTypesMap(file.File_Extension__c)}`
                return file
            })

            // console.log('this.files')
            // console.log(JSON.parse(JSON.stringify(this.files)))
        } catch (error) {
            console.error(error)
        } finally {
            this.isLoading = false
        }
    }

    async fetchSettings() {
        this.settings = await getFileSizeLimit({
            cred: ''
        })
        // console.log('settings')
        // console.log(JSON.parse(JSON.stringify(this.settings)))
    }
    
    fetchS3Files() {
        this.fetchSalesforceS3Files()
    }

    handleLoading() {
        this.isLoading = this.isLoading ? false : true
    }

    handleCloseModal() {
        this.showLoadingModal = false
        this.uploadProgress = 0;
        this.uploadProgressTotal = 0;
    }
}

const capitalize = (s) => s[0].toUpperCase() + s.substring(1)