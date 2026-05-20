import { LightningElement, api, track, wire } from 'lwc';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import { isChangeInDataForGraphQLResult } from 'c/neuraCommonUtility';
import { ErrorEvent } from './events';

export default class NeuraFormFilesData extends LightningElement {
    @api get answerIds() {
        return this._answerIds;
    }
    set answerIds(value) {
        this._answerIds = [...value];
    }

    @api shouldDoRefreshGraphQl;

    graphqlQueryResultCalledTimes = 0;

    graphqlResult;

    runOnce = false;

    @wire(graphql, {
        query:  "$graphqlQuery",
        variables: "$variables"
    }) 
    graphqlQueryResult(result) {
        const {data, errors} = result;
        if(data) {
            if(isChangeInDataForGraphQLResult(data, this.graphqlResult) && this.shouldDoRefreshGraphQl) {
                this.graphqlResult = result;

                this.graphqlQueryResultCalledTimes = 1;

                setTimeout(() => {
                    this.initializeComponent(data);
                }, 10);
            } else if(!this.runOnce) {
                this.graphqlQueryResultCalledTimes++;

                if(this.graphqlQueryResultCalledTimes === 1) {
                    const tempAnswerIds = [...this._answerIds];
                    
                    this._answerIds = null;

                    this._answerIds = [...tempAnswerIds];
                } else if(this.graphqlQueryResultCalledTimes === 2) {
                    this.graphqlResult = result;

                    refreshGraphQL(this.graphqlResult);
                    
                    setTimeout(() => {
                        this.initializeComponent(data);
                    }, 10);
                }
            }
        } else if(errors) {
            this.dispatchEvent(new ErrorEvent(errors));

            // this.dispatchEvent(new CustomEvent('load', {
            //     detail: {
            //         value: { ContentDocumentLink: [] }
            //     }
            // }));
        } else {
            console.log('graphqlQueryResult: no data and no errors');
        }
    }

    initializeComponent(data) {
        if(data.uiapi.query.ContentDocumentLink.edges && data.uiapi.query.ContentDocumentLink.edges.length) {
            this.dispatchEvent(new CustomEvent('load', {
                detail: {
                    value: this.getFormattedGraphQLData(data)
                }
            }));
        }
        
        if(this.graphqlQueryResultCalledTimes === 1 && !data.uiapi.query.ContentDocumentLink.edges.length) {
            this.dispatchEvent(new CustomEvent('load', {
                detail: {
                    value: { ContentDocumentLink: [] }
                }
            }));
        }

        this.runOnce = true;
    }

    @track _answerIds;

    processEdges(edges) {
        let properties = [];
        edges.forEach(item => {
            const node = item.node;
            properties.push(this.processFieldValues(node));
        });
        return properties;
    }

    processFieldValues(node) {
        let property = {};
        for (let field in node) {
            //field with _drafts is coming only on mobile
            //Don't know the reason of it, that's the method was not getting implemented
            if(field !== '_drafts') {
                const obj = node[field];
                let value;
                if (field === 'Id') {
                    value = obj;
                } else if (obj.value) {
                    value = obj.value;
                } else {
                    value = this.processFieldValues(obj);
                }
                property[field] = value;
            }
        }

        return property;
    }

    getFormattedGraphQLData(data) {
        let formattedData = {};
        const queryData = data.uiapi.query;
        for (let item in queryData) {
            formattedData[item] = this.processEdges(queryData[item].edges);
        }
        return formattedData;
    }

    get variables() {
        return {
            LinkedEntityId: this._answerIds
        };
    }

    get graphqlQuery() {
        if(!this._answerIds.length) return undefined;

        return gql`
            query getFilesData($LinkedEntityId: [ID]) {
                uiapi {
                    query {
                        ContentDocumentLink (
                            first: 500
                            where: { LinkedEntityId: { in: $LinkedEntityId } }
                        ) {
                            edges {
                                node {
                                    Id
                                    LinkedEntityId {
                                        value
                                    }
                                    ContentDocument {
                                        Id
                                        LatestPublishedVersion {
                                            Id
                                            Title {
                                                value
                                            }
                                            VersionDataUrl {
                                                value
                                            }
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
}