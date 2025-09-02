import { api, LightningElement } from 'lwc';
import { fileTypesMap } from 'c/awsS3Utilities';
import LightningConfirm from 'lightning/confirm';
import deleteFile from '@salesforce/apex/AWSS3Utilities.deleteFile';
import viewFile from '@salesforce/apex/AWSS3Utilities.viewFile';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class AwsS3TableFiles extends LightningElement {
	@api files = []
	@api allowDelete = false
	@api allowView = false

	sortedBy;
	sortedDirection = 'asc';

	doc = ''
    
    loading = false
    isModalOpen = false;
    modalTitle = '';
    fileType = '';

	get columns() {
		const baseColumns = [
			{
				label: 'File Name',
				fieldName: 'File_Name__c',
				type: 'text',
				sortable: true,
				wrapText: true
			},
			{
				label: 'Type',
				fieldName: 'Type__c',
				type: 'text',
				sortable: true
			},
			{
				label: 'Extension',
				fieldName: 'File_Extension__c',
				type: 'text',
				sortable: true
			},
			{
				label: 'Size',
				fieldName: 'Size_Label__c',
				type: 'text',
				sortable: true,
				cellAttributes: { alignment: 'center' }
			},
			{
				label: 'Visibility',
				fieldName: 'Visibility__c',
				type: 'text',
				sortable: true
			},
			// {
			// 	label: 'sObject Type',
			// 	fieldName: 'sObject_Type__c',
			// 	type: 'text',
			// 	sortable: true
			// },
			{
				label: 'Versions',
				fieldName: 'Versions__c',
				type: 'number',
				sortable: true,
				cellAttributes: { alignment: 'center' }
			},
			// {
			// 	label: 'S3 Path',
			// 	fieldName: 'S3_Path__c',
			// 	type: 'text',
			// 	sortable: true,
			// 	wrapText: true
			// },
			// {
			// 	label: 'Key',
			// 	fieldName: 'Key__c',
			// 	type: 'text',
			// 	sortable: true,
			// 	wrapText: true
			// },
			{
				label: 'Last Modified',
				fieldName: 'File_Last_Modified_Epoch__c',
				type: 'date',
				sortable: true,
				typeAttributes: {
					year: 'numeric',
					month: 'short',
					day: '2-digit',
					hour: '2-digit',
					minute: '2-digit'
				}
			}
		];

		// Add action column if view or delete is allowed
		if (this.allowView || this.allowDelete) {
			const actions = [];
			
			if (this.allowView) {
				actions.push({
					label: 'View',
					name: 'view'
				});
				actions.push({
					label: 'View in tab',
					name: 'viewInTab'
				});
			}
			
			if (this.allowDelete) {
				actions.push({
					label: 'Delete',
					name: 'delete'
				});
			}

			baseColumns.push({
				type: 'action',
				typeAttributes: { rowActions: actions }
			});
		}

		return baseColumns;
	}

	handleSort(event) {
		this.sortedBy = event.detail.fieldName;
		this.sortedDirection = event.detail.sortDirection;
		
		// Create a copy of the files array for sorting
		const sortedFiles = [...this.files];
		const isReverse = this.sortedDirection === 'desc';
		
		sortedFiles.sort((a, b) => {
			let aVal = a[this.sortedBy] || '';
			let bVal = b[this.sortedBy] || '';
			
			// Handle different data types
			if (typeof aVal === 'string') {
				aVal = aVal.toLowerCase();
				bVal = bVal.toLowerCase();
			}
			
			if (aVal < bVal) {
				return isReverse ? 1 : -1;
			}
			if (aVal > bVal) {
				return isReverse ? -1 : 1;
			}
			return 0;
		});
		
		// Dispatch event to parent component with sorted data
		this.dispatchEvent(new CustomEvent('filesorted', {
			detail: { sortedFiles }
		}));
	}

	handleRowAction(event) {
		const actionName = event.detail.action.name;
		const row = event.detail.row;

		console.log({
			actionName,
			row: JSON.stringify(row)
		})

		if (actionName === 'delete') {
			this.handleDelete(row)
		} else if (actionName.includes('view')) {
			console.log('log .5');
			
			this.handleView(actionName, row)
		} 
	}

	async handleDelete(row) {
        const fileKey = row.Key__c;
        const fileId = row.Id;
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

	async handleView(name, row) {
		console.log('here 1');
		

        const key = row.Key__c
        const url = await viewFile({ key })
        
        if (name === 'viewInTab') {
            window.open(url, '_blank').focus()
        } else {
            this.doc = url
            this.modalTitle = row.Title_Name__c;
            this.isModalOpen = true;
        }
    }

	closeModal() {
        this.isModalOpen = false;
        this.doc = ''
    }
}