# EssentialOpen

This repository provides a comprehensive suite of scripts designed to deploy the open-source release of the [Essential Project](https://enterprise-architecture.org/), alongside a compatible API and a dedicated admin panel.

The application is fully containerized using Docker and Docker Compose, enabling you to seamlessly run the entire stack locally.

Additionally, the repository includes configuration scripts to integrate Azure Entra ID (formerly Azure AD). This allows for a completely functional deployment with integrated authentication via OAuth2-Proxy, providing a secure and scalable environment for Enterprise Architecture management.

These scripts automate setup, containerization, and authentication configuration, ensuring a smooth transition from local development to cloud deployment.

## Getting Started

To begin setting up the Essential Open Source EA Tool, follow these steps:

1. **Clone the repository:**

   ```bash
   git clone git@github.com:terryvel/EssentialOpen.git
   cd EssentialOpen
   ```

2. **Prepare the environment:**
   Build the required Docker images by running the setup script:

   ```bash
   sh scripts/1_prepare.sh
   ```

   > **Note:** Save the password shown at the end of the script execution (`PUBLISH_PASSWORD`). You will need it to publish changes to "Essential Viewer" using Protégé.

   ![Sample 1_prepare.sh results](assets/prepare_results_sample.png)

3. **Run the project locally (without authentication):**

   ```bash
   docker compose -f docker-compose-noauth.yml up
   ```

**Accessing Local Services:**

- **Essential Viewer:** [http://localhost](http://localhost)  
  ![Essential Viewer running in Docker locally](assets/essential_viewer_localhost.png)
- **Essential Open API:** [http://localhost/api/](http://localhost/api/)  
  ![Essential Open API running in Docker locally](assets/essential_api_localhost.png)
- **Essential Open Admin:** [http://localhost/admin/](http://localhost/admin/)  
  ![Essential Open Admin running in Docker locally](assets/essential_admin_localhost.png)

## Configure Azure Entra ID (Authentication)

This step-by-step guide configures Azure Entra ID authentication so that only authenticated users can access the Essential Viewer. This setup can also be easily adapted to use other corporate identity providers.

### 1. Set up Entra ID Authentication

Run the following configuration script. It will create App Registrations, apply variables, and generate a secure environment for deployment.

```bash
bash scripts/2_configure_entra_id.sh
```

Here is an example of how the script should finish executing:

![Sample 2_configure_entra_id.sh results](assets/configure_entra_id_sample.png)

### 2. Run container locally with auth

Start the services using the default `docker-compose.yml` (which includes the OAuth2-Proxy configuration):

```bash
docker compose up
```

You can now access Essential Viewer with secure authentication at [http://localhost](http://localhost).

![Essential Viewer running in Docker locally with auth](assets/essential_viewer_localhost_auth.png)

## Conclusion & Acknowledgements

I hope these steps help as many people as possible to test Essential—a fantastic Enterprise Architecture tool—and that these tests help you convince your board to invest in an EA tool (preferably Essential).

I would like to express my sincere gratitude to **Urbiwanus** for his work on the [essential-project-docker](https://github.com/Urbiwanus/essential-project-docker) repository. His project served as a significant reference and inspiration for me to get started with this containerized setup. Without his contributions, this journey would have been much more challenging. Thank you, Urbiwanus!
