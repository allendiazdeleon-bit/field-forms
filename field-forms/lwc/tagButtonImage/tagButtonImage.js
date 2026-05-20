import { api, track, LightningElement, wire } from 'lwc';
import { gql, graphql } from 'lightning/uiGraphQLApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecord } from 'lightning/uiRecordApi';

export default class FilePrimer extends LightningElement {
    @api recordId;
    @api objectApiName;
    @track imageData;
    @track errors;
    @api assetrecordid;
    @track contentVersionFields;
    @track contentVersionIds;
    @track contentVersionRecord;
    @track contentVersionRecordId = [];
      contentVersionRecordIndex = 0
    @track contentDocumentFields;
    @track contentDocumentIds;
    @track contentDocRecord;
    
    @track contentRecordId;
    @track fileUrlsMap = new Map(); // Map to store file URLs for each asset
  //  @track queryResult;
    @track showSpinner = false;

    connectedCallback() {
        // Hardcoded Record ID (You can set it dynamically as needed)
        //refreshGraphQL(this.graphqlQueryResult)
        this.recordId = this.assetrecordid;
    }

    objectFields(objectFields, objectType) {
        let keys = Object.keys(objectFields);
        let fields = keys.map((f) => {
            return `${objectType}.${f}`;
        });
        return fields;
    }

    @wire(getObjectInfo, { objectApiName: 'ContentDocument' })
    getObjectInfo({ error, data }) {
        if (data) {
            this.contentDocumentFields = this.objectFields(data.fields, 'ContentDocument');
        } else {
            console.log('getObjectInfo error -> ', JSON.stringify(error));
            this.errors = error;
        }
    }

    @wire(getObjectInfo, { objectApiName: 'ContentVersion' })
    getVersionObjectInfo({ error, data }) {
        if (data) {
            this.contentVersionFields = this.objectFields(data.fields, 'ContentVersion');
        } else {
            console.log('getVersionObjectInfo error -> ', error);
            this.errors = error;
        }
    }

    getContentRecordIds(data) {
        let documentIds = [];
        let versionIds = [];
        let contentLinks = data.uiapi.query.ContentDocumentLink.edges;
        for (let index = 0; index < contentLinks.length; index++) {
            const contentLink = contentLinks[index];
            documentIds.push(contentLink.node.ContentDocument.Id);
            versionIds.push(contentLink.node.ContentDocument.LatestPublishedVersion.Id);
        }
        this.contentDocumentIds = documentIds;
        this.contentVersionIds = versionIds;

        this.contentRecordId = this.contentDocumentIds[0];
        this.contentVersionRecordId = this.contentVersionIds[0];

        this.showSpinner = true;

        if(this.contentDocumentIds.length === 0) {
            let noImageData = new Map();
            noImageData.set(this.recordId, []);
            const event = new CustomEvent("latestimageurlchange", {
                detail: {
                    fileUrlsMap: noImageData, // Pass the noImageData
                },
            });
            this.dispatchEvent(event);
        }
    }

   @wire(getRecord, {
    recordId: '$contentVersionRecordId',
    fields: '$contentVersionFields',
})
wiredVersions({ error, data }) {
    if (error) {
        console.log('wiredVersions Error: ' + error);
        this.errors = error;
    } else if (data) {
        this.contentVersionRecord = data;
        const fileType = this.contentVersionRecord.fields.FileType.value;

        const imageFileExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'ico'];

        alert(this.contentVersionRecord.fields.VersionDataUrl.value);

        if (imageFileExtensions.includes(fileType.toLowerCase())) {
            this.setFileUrl(this.contentVersionIds.indexOf(this.contentVersionRecordId), this.contentVersionRecord.fields.VersionDataUrl.value);
        } else {
            console.log('Unsupported FileType: ' + fileType);
        }

        this.contentVersionIds.shift();
        if (this.contentVersionIds.length > 0) {
            this.contentVersionRecordId = this.contentVersionIds[0];
        } else {
            this.showSpinner = false;
        }
    }
}

setFileUrl(index, url) {
    if (index >= 0 && index < this.contentDocumentIds.length) {
        const assetId = this.assetrecordid; // Get the asset ID
        if (!this.fileUrlsMap.has(assetId)) {
            // Initialize an array for each asset if it doesn't exist
            this.fileUrlsMap.set(assetId, []);
        }
        // Store the URL and CreatedDate in the array for the specific asset
        this.fileUrlsMap.get(assetId).push({
            imageUrl: url,
            CreatedDate: this.contentVersionRecord.fields.CreatedDate.value, // Use the CreatedDate from ContentVersion
        });
        
    }
    this.getLatestImages();
}


    @wire(getRecord, {
        recordId: '$contentRecordId',
        fields: '$contentDocumentFields',
    })
    wiredDocs({ error, data }) {
        if (error) {
            console.log('wiredDocs Error: ' + error);
            this.errors = error;
        } else if (data) {
            this.contentDocRecord = data;
            //this.contentDocumentIds.shift();
            if (this.contentDocumentIds.length > 0) {
                this.contentRecordId = this.contentDocumentIds[0];
            }
        }
    }

    @wire(graphql, {
        query: '$contentDocumentLinkCombinedQuery',
        variables: '$contentDocumentCombinedLinkVariables',
    })
    graphqlQueryResult({ data, errors }) {
        if (data) {
            alert('data' + JSON.stringify(data));
          //  this.queryResult = JSON.stringify(data);
            this.getContentRecordIds(data);
        } else if (errors) {
            console.log('graphqlQueryResult errors ' + errors);
            this.errors = errors;
        }
    }

   get contentDocumentLinkCombinedQuery() {
        return gql`
            query contentDocumentLink($linkedEntityId: ID = "") {
                uiapi {
                    query {
                        ContentDocumentLink(
                            where: { LinkedEntityId: { eq: $linkedEntityId } }
                           
                        ) {
                            edges {
                                node {
                                    Id
                                    ContentDocument {
                                        Id
                                        LatestPublishedVersion {
                                            Id
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        `;
    }

    get contentDocumentCombinedLinkVariables() {
        return {
            linkedEntityId: this.recordId,
        };
    }

  getLatestImages() {
    // Create and dispatch the custom event with the entire fileUrlsMap
    const event = new CustomEvent("latestimageurlchange", {
        detail: {
            fileUrlsMap: this.fileUrlsMap, // Pass the entire fileUrlsMap
        },
    });
    this.dispatchEvent(event);
    
}

}