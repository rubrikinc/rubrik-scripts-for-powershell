# Service accounts:				
Service accounts allow users to access CDM APIs through scripts or other automation methods.		To access CDM APIs through scripts or other automation methods, a user can create a service account that can be seen by all admins. When a user creates a service account, the ID and password for that account is only shown once. To see it again, a user must rotate the password, which will bring up the credentials once more (the same ID but a different password because it was rotated). A service account can fetch an API token by an API call, which is then used by the same automation script.

A POST request to the /service_account/session endpoint generates an API token with a 24-hour time to live (TTL). This token inherits the permissions of the service account that was used to create
the token. A service account can be assigned roles that specify a set of permissions for the API tokens created by that service account. A tenant organization administrator can see all service accounts within the organization and global administrators can see all service accounts on the Rubrik cluster.

## Adding a service account			
Add a service account to generate client credentials.				
### Procedure	
<ol>
<li>Log in to the Rubrik CDM web UI using the admin account.
<li>Click the gear icon.
<li>Click Users. The Users page appears.
<li>Click Service Accounts > Add Service Account. The Add Service Account dialog box appears.
<li>In the Service Account Name, type the name of the service account.
<li>In Roles, select either AdministratorRole.
<li>Click Add. The Service Account ID and Secret dialog box appear.
<li>Click Copy Secret. Store the service account ID and secret in a secure location. The secret is copied to the clipboard.
</ol>

### Result
The Rubrik cluster adds a service account and generates credentials.

## Editing a service account
Edit a service account to change the name of the service account and the user roles in that service account.
### Procedure
<ol>
<li>Log in to the Rubrik CDM web UI using the admin account.
<li>Click the gear icon.
<li>Click Users. The Users page appears.
<li>Click Service Accounts. The list of service accounts appears.
<li>Open the ellipsis menu of the service account and click Edit. The Edit Service Account dialog box appears.
<li>Edit the name of the service account or roles.
<li>Click Update.				 					
</ol>

### Result				
The Rubrik cluster updates the service account with the new information.

## Deleting a service account
Delete a service account.
### Procedure
<ol>
<li>Log in to the Rubrik CDM web UI using the admin account.
<li>Click the gear icon.
<li>Click Users. The Users page appears.
<li>Click Service Accounts. The list of service accounts appears.
<li>Open the ellipsis menu of the service account and click Delete. The Delete Service Account confirmation dialog box appears.
<li>Click Delete. A confirmation message appears to indicate the selected service account has been deleted.
</ol>

### Result
The Rubrik cluster deletes the selected service account.

## Rotating the client secret
Generate a new client secret for a service account periodically for security purposes.
### Procedure
<ol>
<li>Log in to the Rubrik CDM web UI using the admin account.
<li>Click the gear icon.
<li>Click Users. The Users page appears.	
<li>Click Service Accounts. The list of service accounts appears.
<li>From the ellipsis menu of a service account, click Rotate Secret. The Rotate Secret dialog box appears.
<li>Select Expire all existing sessions immediately to invalidate the existing secret.
<li>Click Confirm.
<li>The new client secret appears.
<li>The Service Account ID and Secret dialog box appears.
<li>Click Copy Secret.
<li>Store the new secret in a secure location. The secret is copied to clipboard.				 					
</ol>

### Result				
The Rubrik cluster generates a new secret for the service account. 
				
			
		

