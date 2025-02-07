# Installation
http://luarocks.org/modules/newage/kong-plugin-google-storage-adapter

`luarocks install kong-plugin-google-storage-adapter`

```
custom_plugins = google-storage-adapter
```

`Reminder: don't forget to update the custom_plugins directive for each node in your Kong cluster.`

# API

POST :8001/plugins
```
{
	"service": null,
	"tags": null,
	"route": null,
	"consumer": null,
	"name": "google-storage-adapter",
	"instance_name": "google-storage-adapter",
	"created_at": 1701430334,
	"updated_at": 1703150984,
	"protocols": [
		"http",
		"https"
	],
	"enabled": true,
	"config": {
		"request_authentication": {
			"secret": "GOOGLE_SECRET",
			"bucket_name": "landings-stage",
			"enabled": true,
			"log": true,
			"access_id": "GOOGLE_ACCESS_ID"
		},
		"path_transformation": {
			"enabled": true,
			"log": true,
			"prefix": "/sites"
		},
		"service_headers" : {
			"enabled": true,
			"log": true
		}
	},
	"id": "04752261-8efd-4898-9cbc-84573e6c8ee6"
}
```
## Deploy

1. Make changes to the code
2. Update version in file `kong-plugin-google-storage-adapter-{version}-{revision}` and change file name
2. Push it to master
3. Create tag by version `git tag 0.3.3-0 -m "<tag message>"`
4. Push tag `git push origin 0.3.3-0`
5. Create pack `luarocks pack kong-plugin-google-storage-adapter-1.8.0-0.rockspec`
6. Upload pack `luarocks upload kong-plugin-google-storage-adapter-1.8.0-0.rockspec --api-key=`. Get API key from keeper