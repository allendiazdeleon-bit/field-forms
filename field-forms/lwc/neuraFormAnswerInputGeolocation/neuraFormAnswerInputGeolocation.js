import { LightningElement, track, api } from 'lwc';
import { getLocationService } from 'lightning/mobileCapabilities';

export default class NeuraFormAnswerInputGeolocation extends LightningElement {
    @api get val() {
        return `${String(this.latitude)}, ${String(this.longitude)}`;
    } set val(value) {
        const geolocation = value.split(',');
        if(geolocation.length === 2) {
            this.latitude = geolocation[0].trim();
            this.longitude = geolocation[1].trim();
        }
    }

    @track title = 'Capture Geolocation';
    @track latitude;
    @track longitude;

    // Cache the Nimbus location service handle. isAvailable() is the only reliable
    // way to detect the FSL mobile runtime; @salesforce/client/formFactor returns
    // "Small" in LWC Offline regardless of device, so it cannot be used here.
    _locationService;

    get locationService() {
        if (this._locationService === undefined) {
            try {
                this._locationService = getLocationService();
            } catch (e) {
                this._locationService = null;
            }
        }
        return this._locationService;
    }

    captureGeolocation(event) {
        event.preventDefault();

        this.dispatchEvent(new CustomEvent('capturelocation', {
            detail: true,
            composed: true,
            bubbles: true
        }));

        if (this.locationService && this.locationService.isAvailable()) {
            this.getGeolocationOnOtherDevices();
        } else {
            this.getGeolocationOnDesktop();
        }
    }

    async getGeolocationOnDesktop() {
        if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(
                (position) => {
                    this.latitude = position.coords.latitude;
                    this.longitude = position.coords.longitude;
                    this.title = 'Geolocation Captured';
                    this.dispatchEvent(new CustomEvent('change', {
                        detail: {
                            value: `${String(this.latitude)}, ${String(this.longitude)}`
                        }
                    }));

                    this.dispatchEvent(new CustomEvent('capturelocation', {
                        detail: false,
                        composed: true,
                        bubbles: true
                    }));
                },
                (error) => {
                    console.error('Error getting geolocation:', error);
                    this.title = 'Error capturing geolocation';

                    this.dispatchEvent(new CustomEvent('capturelocation', {
                        detail: false,
                        composed: true,
                        bubbles: true
                    }));
                }
            );
        } else {
            console.error('Geolocation is not supported by this browser.');
            this.title = 'Geolocation not supported';
        }
    }

    async getGeolocationOnOtherDevices() {
        // Request the device's current geolocation via Nimbus plugin
        this.locationService
            .getCurrentPosition({ enableHighAccuracy: true })
            .then((result) => {
                // Extract latitude and longitude from the result
                this.latitude = result.coords.latitude;
                this.longitude = result.coords.longitude;
                this.title = 'Geolocation Captured';

                this.dispatchEvent(new CustomEvent('change', {
                    detail: {
                        value: `${String(this.latitude)}, ${String(this.longitude)}`
                    }
                }));
            })
            .catch((error) => {
                console.error(error);
                this.title = 'Error capturing geolocation';
            })
            .finally(() => {
                this.dispatchEvent(new CustomEvent('capturelocation', {
                    detail: false,
                    composed: true,
                    bubbles: true
                }));
            });
    }

    get showGeolocation() {
        return this.latitude && this.longitude;
    }
}