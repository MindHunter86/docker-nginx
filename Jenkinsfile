pipeline {
  agent {
    node {
      label 'is-builder1.mh00s.net'
    }

  }
  stages {
    stage('Preparation') {
      steps {
        git(url: 'git@github.com:MindHunter86/docker-nginx.git', branch: 'master', credentialsId: 'github_docker-nginx')
        echo 'all ok'
      }
    }
    stage('Build') {
      agent {
        dockerfile {
          filename 'Dockerfile'
        }

      }
      steps {
        echo 'docker ok?'
      }
    }
  }
}