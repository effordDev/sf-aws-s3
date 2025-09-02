import { api, LightningElement } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import deleteFile from '@salesforce/apex/AWSS3Utilities.deleteFile';
import viewFile from '@salesforce/apex/AWSS3Utilities.viewFile';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ApplicationS3FileInputList extends LightningElement {
    @api allowView = false
    @api allowDelete = false
    @api files = []

    doc = ''
    
    loading = false
    isModalOpen = false;
    modalTitle = '';
    fileType = '';

    async handleDelete(event) {
        const fileKey = event.target.dataset.key;
        const fileId = event.target.dataset.id;
        const result = await LightningConfirm.open({
            message: 'Are you sure you want to delete this file? This action cannot be undone.',
            variant: 'headerless',
            label: 'Delete File',
        });

        if (!result) {
            return
        }

        try {
            this.loading = true

            const isDeleted = await deleteFile({ key: fileKey, id: fileId})

            if (isDeleted) {
                this.files = this.files.filter(file => file.Key__c !== fileKey);
            }

            this.dispatchEvent(
                new CustomEvent('filedeleted', {
                    detail: {
                        fileIdDeleted: fileId
                    }
                })
            )

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'File deleted successfully.',
                    variant: 'success'
                })
            );

        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error Deleting File',
                    message: error.body.message,
                    variant: 'error'
                })
            );
        } finally {
            this.loading = false
        }
        
    }
    
    closeModal() {
        this.isModalOpen = false;
        this.doc = ''
    }
    
    async handleView(event) {

        const name = event.currentTarget.name

        const key = event.target.dataset.key
        const url = await viewFile({ key })
        
        if (name === 'viewInTab') {
            window.open(url, '_blank').focus()
        } else {
            this.doc = url
            this.modalTitle = event.target.dataset.title;
            this.isModalOpen = true;
        }
    }
}