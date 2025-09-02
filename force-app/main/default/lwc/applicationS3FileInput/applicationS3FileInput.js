import { api, track, LightningElement } from 'lwc';
import LightningAlert from 'lightning/alert';
import postFile from '@salesforce/apex/AWSS3Utilities.postFile'
import getRecordApiName from '@salesforce/apex/AWSS3Utilities.getRecordApiName'
import createSalesforceS3File from '@salesforce/apex/AWSS3Utilities.createSalesforceS3File'
import getSalesforceApplicationS3Files from '@salesforce/apex/AWSS3Utilities.getSalesforceApplicationS3Files'
import { fileTypesMap, createObjectUrlFromPresignedUrl } from 'c/awsS3Utilities'
import getFileSizeLimit from '@salesforce/apex/AWSS3Utilities.getFileSizeLimit'

export default class ApplicationS3FileInput extends LightningElement {
    @api recordId = ''
    @api sectionId = ''
    @api language = ''
    @api languages = []
    @api readOnly = false
    @track _detail = {};

    files = []

    settings = {}
    modalMessage = ''
    showLoadingModal = ''

    showLoadingModal = false
    uploadProgress = 0
    uploadProgressTotal = 0

    async connectedCallback() {
        // console.log('s3 file upload')
        // console.log(JSON.parse(JSON.stringify(this.detail)))

        try {
            this.recordApiName = await getRecordApiName({
                recordId: this.recordId
            })

            await this.fetchSettings()

    
           await this.fetchSalesforceApplicationS3Files()
        } catch (error) {
            console.log(error)
        }
    }

    @api get detail() {
		return this._detail;
	}
	set detail(value) {
		this._detail = Object.assign({}, value);
	}

    @api get completed() {

        if (!this.required) {
            return true
        }
        if (this.required && this.minUploadsReached) {
            return true
        }

        // if (!this.minUploadsReached && this.required) {
        //     return false
        // }

		return false
	}

    get id() {
		return this.detail?.Id;
	}
    get label() {
		return this.language === "English"
			? this.detail?.Field_Label__c
			: this.languages
					.filter((lang) => lang.Application_Detail__c === this.id)
					.find((item) => item.Language__c === this.language)
					?.Translated_Text__c || this.detail?.Field_Label__c;
	}
    get required() {
		return this.detail?.Required__c || !this.minUploadsReached;
	}
    get showUpload() {
        return !this.readOnly 
    }
    get boxClass() {
		return this.completed ? `slds-box` : `slds-box not-complete`;
	}
    get acceptedFormats() {
		return this.detail?.Accepted_File_Types__c?.split(";") || []
	}
	get formattedAcceptedFormats() {
		return this.acceptedFormats.join(", ");
	}
    get allowDelete() {
		return !this.readOnly 
	}
    get minimumUploadNumber() {
        return this.detail?.Minimum_Uploads_Required__c || 0
    }
    get maximumUploadNumber() {
        return this.detail?.Maximum_Uploads_Allowed__c || 10
    }
    get minUploadsReached() {
        return this.files.length >= this.minimumUploadNumber
    }
    get maxUploadsReached() {
        return this.files.length == this.maximumUploadNumber
    }
    get allowUpload() {
        // if (this.minUploadsReached) {
        //     return false
        // }
        if (this.maxUploadsReached) {
            return false
        }
        if (this.readOnly) {
            return false
        }
        return true
    }

    get prefix() {
        return `Application__c/${this.recordId}/external/${this.s3FileObject}` 
    }
    get s3FileObject() {
        return this.detail?.S3_File_Object__c || 'fallbackObject'
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

    async handleUpload(event) {

        if (event.detail.files.length > 1) {
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
            
            // console.log({file})
            // console.log('upload complete => ')
            // console.log({results})

            const s3File = {
                Parent_Id__c: this.recordId,
                sObject_Type__c: this.recordApiName,
                S3_File_Object__c: this.s3FileObject,
                Visibility__c: 'external',
                File_Name__c: results.Name,
                Key__c: results.Key,
                S3_Path__c: results.Key.substring(0, results.Key.lastIndexOf('/')),
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
        
            await this.fetchSalesforceApplicationS3Files()

            this.dispatchEvent(
                new CustomEvent("detailchange", {
                    composed: true,
                    bubbles: true,
                    detail: {
                        Id: this.id,
                        Input_Files_Uploaded__c: this.files.length
                    }
                })
		    );

            this.modalMessage = 'File uploaded successfully.'
        } catch (error) {
            this.modalMessage = 'An error has occurred.'
            console.log('error ', error)

            await LightningAlert.open({
                message: error?.body?.message || error?.message || 'An unknown error occurred.',
                theme: 'error',
                label: 'Error!',
            });
        } finally {

        }
    }

    async uploadFile(file) { 
        const key = `${this.prefix}/${file.name}`

        const fileData = {
            Name: file.name,
            Type: file.type,
            Method: 'PUT',
            Key: key,
            length: file.size,
            visibility: 'external'
        };

        const signedUrl = await postFile({ key });

        // console.log({ signedUrl });

        const result = await this.performUpload(file, signedUrl, fileData);
        return result;
    }

    async performUpload(file, signedUrl, fileData) {

        return new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();

            xhr.open('PUT', signedUrl, true);
            xhr.setRequestHeader('Content-Type', file.type);

            xhr.upload.onprogress = (event) => {
                if (event.lengthComputable) {
                    

                    this.uploadProgress = event.loaded;
                    this.uploadProgressTotal = event.total;
                }
            };

            xhr.onload = () => {
                if (xhr.status === 200 || xhr.status === 204) {
                    // console.log('Upload success:', xhr.responseText);

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

    async fetchSalesforceApplicationS3Files() {
        try {
            this.isLoading = true

            // console.log('this.prefix')
            // console.log(this.prefix)

            this.files = (await getSalesforceApplicationS3Files({
                recordId: this.recordId,
                path: this.prefix
            })).map(file => {
                    file.icon = `doctype:${fileTypesMap(file.File_Extension__c)}`
                return file
            })



            // this.files = (await getS3ContentVersions({
            //     recordId: this.recordId,
            //     visibility: this.bucketVisibility
            // })).map(file => {
            //     file.icon = `doctype:${fileTypesMap(file.FileExtension)}`
            //     return file
            // })

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

    handleFileDeleted(event) {
        const id = event.detail.fileIdDeleted

        this.files = this.files.filter(file => file.Id !== id);
    }

    fetchS3Files() {
        this.fetchSalesforceApplicationS3Files()
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